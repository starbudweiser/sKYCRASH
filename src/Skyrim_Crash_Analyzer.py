"""sKYCRASH — analyse des logs Skyrim Special Edition (macOS)."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import socle_qt
from PyQt6.QtCore import QFileSystemWatcher, QSize, Qt, QThread, QTimer, pyqtSignal
from PyQt6.QtGui import QAction, QColor, QCursor, QFontMetrics, QKeySequence, QPalette, QTextCharFormat
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFileDialog, QFormLayout, QFrame,
    QGridLayout, QGroupBox, QHBoxLayout, QLineEdit, QListWidget, QListWidgetItem, QMenuBar, QMessageBox, QPushButton,
    QScrollArea, QSizePolicy, QSplitter, QTabWidget, QTextEdit, QVBoxLayout, QWidget, QLabel, QCheckBox,
)

import ai_client
import ai_format
import audit_engine
import diagnostic
import guard
import jev_client
import i18n
import insights
import knowledge_updater
from i18n import L, N_

APP_NAME = "sKYCRASH"
HOME = Path.home()
DOCS = HOME / "Documents"
CONFIG_DIR = HOME / "Library" / "Application Support" / "SkyrimCrashAnalyzer"
CONFIG_FILE = CONFIG_DIR / "config.json"

MAX_LOG_BYTES = 20 * 1024 * 1024  # garde-fou: au-delà, lecture de la fin seulement
TAIL_LINES = 80
MAX_CARDS = 18
ERROR_RE = re.compile(
    r"(failed|error|cannot|missing|exception|access violation|null pointer)", re.I
)


def default_folders() -> dict:
    mg = DOCS / "My Games"
    return {
        "SKYRIM": [
            str(mg / "Skyrim Special Edition" / "SKSE"),
            str(mg / "Skyrim Special Edition" / "SKSE" / "Crashlogs"),
            str(mg / "Skyrim Special Edition" / "Logs" / "Script"),
        ],
    }


def _read_config_file() -> dict:
    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}  # config absente ou corrompue -> valeurs par défaut


def _write_config_file(data: dict) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    except OSError as e:
        print(f"Config save failed: {e}", file=sys.stderr)


def load_config() -> dict:
    cfg = default_folders()
    override = os.environ.get("SKYRIM_CA_FOLDERS")
    if override:  # mode preview : dossiers imposés, config utilisateur intacte
        cfg["SKYRIM"] = [p for p in override.split(os.pathsep) if p]
        return cfg
    data = _read_config_file()
    for game in cfg:
        val = data.get(game)
        if isinstance(val, list) and all(isinstance(p, str) for p in val):
            cfg[game] = val
    return cfg


def save_config(cfg: dict) -> None:
    if os.environ.get("SKYRIM_CA_FOLDERS"):
        return  # mode preview : ne rien écrire
    data = _read_config_file()
    data.update(cfg)
    _write_config_file(data)


def load_settings() -> dict:
    s = dict(ai_client.DEFAULT_SETTINGS)
    stored = _read_config_file().get("settings")
    if isinstance(stored, dict):
        s.update({k: v for k, v in stored.items() if k in s and isinstance(v, str)})
    if not (isinstance(stored, dict) and "provider" in stored):
        provider, model = ai_client.detect_default_provider(s["ollama_url"])  # IA locale par défaut si dispo
        s["provider"] = provider
        if model:
            s["ollama_model"] = model
    if s.get("language") not in i18n.LANGS:
        s["language"] = i18n.system_lang()
    return s


def save_settings(settings: dict) -> None:
    data = _read_config_file()
    data["settings"] = settings
    _write_config_file(data)


def gather_audit_files(folders: list, limit: int=40) -> list:
    """Fichiers .log/.txt des dossiers configurés, les plus récents d'abord."""
    found = []
    for folder in folders:
        if not os.path.isdir(folder):
            continue
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for n in names:
            if n.lower().endswith((".log", ".txt")):
                p = os.path.join(folder, n)
                try:
                    if os.path.isfile(p):
                        found.append((os.path.getmtime(p), p))
                except OSError:
                    continue
    found.sort(reverse=True)
    # les crash logs récents passent toujours, même noyés parmi des dizaines de journaux plus récents
    crashes = [p for _m, p in found if CRASH_NAME_RE.match(os.path.basename(p))][:audit_engine.MAX_CRASH_LOGS]
    rest = [p for _m, p in found if p not in crashes]
    return crashes + rest[:max(0, limit - len(crashes))]


def read_lines(path: str) -> list:
    """Lit un log (utf-8, sinon utf-16). Tronque les fichiers volumineux."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > MAX_LOG_BYTES:
                f.seek(-MAX_LOG_BYTES, os.SEEK_END)
            raw = f.read()
    except OSError:
        return []
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        text = raw.decode("utf-16", errors="ignore")
    else:
        text = raw.decode("utf-8", errors="ignore")
    return text.splitlines()


def scan_for_errors(path: str):
    for line in reversed(read_lines(path)[-TAIL_LINES:]):
        if ERROR_RE.search(line):
            return line.strip()
    return None


LOG_NAME_RE = re.compile(r"\.log(\.?\d+)?$", re.I)  # .log, .log0, .log.1


def is_log_name(name: str) -> bool:
    return bool(LOG_NAME_RE.search(name))


def list_logs(folders: list) -> list:
    """Retourne [(nom, dossier, chemin_complet, mtime)] des .log/.log0 existants."""
    out = []
    for folder in folders:
        if not os.path.isdir(folder):
            continue
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for n in names:
            p = os.path.join(folder, n)
            if is_log_name(n) and os.path.isfile(p) and not os.path.islink(p):
                try:
                    out.append((n, folder, p, os.path.getmtime(p)))
                except OSError:
                    continue
    return out


CRASH_NAME_RE = re.compile(r"^crash[-_].*\.log$", re.I)
MAX_ARCHIVED_CRASHES = 50


def _archive_crash(path: str, folder: str) -> None:
    """Déplace un crash log dans le dossier d'archive (lu par l'historique), sans écraser."""
    dest_dir = os.path.join(folder, insights.ARCHIVE_DIR)
    os.makedirs(dest_dir, exist_ok=True)
    stem, ext = os.path.splitext(os.path.basename(path))
    dest, k = os.path.join(dest_dir, stem + ext), 1
    while os.path.exists(dest):
        dest, k = os.path.join(dest_dir, f"{stem}-{k}{ext}"), k + 1
    os.rename(path, dest)
    old = sorted((os.path.getmtime(os.path.join(dest_dir, n)), n) for n in os.listdir(dest_dir)
                 if CRASH_NAME_RE.match(n))
    for _m, n in old[:-MAX_ARCHIVED_CRASHES]:  # on garde les plus récents
        os.remove(os.path.join(dest_dir, n))


def skse_log_dir(folders: list) -> str:
    """Dossier « My Games/Skyrim Special Edition/SKSE » : journal SKSE et rapports de Crash Logger."""
    for docs in insights._docs_dirs(folders) + [str(DOCS / "My Games" / "Skyrim Special Edition")]:
        d = os.path.join(docs, "SKSE")
        if os.path.isdir(d):
            return d
    return ""


def with_skse_dir(game_folders: dict) -> dict:
    """Dossiers configurés + dossier SKSE, toujours analysé même s'il a été retiré des réglages."""
    out = {g: list(f) for g, f in game_folders.items()}
    every = [f for fs in out.values() for f in fs]
    d = skse_log_dir(every)
    if d and out and os.path.normpath(d) not in {os.path.normpath(f) for f in every}:
        next(iter(out.values())).append(d)
    return out


def purge_logs(folders: list) -> tuple:
    """Supprime les logs des dossiers configurés (non récursif) ; les crash logs sont archivés.

    Retourne (supprimés, archivés, erreurs).
    """
    deleted, archived, errors = 0, 0, []
    for name, folder, path, _m in list_logs(folders):
        try:
            if CRASH_NAME_RE.match(name):
                _archive_crash(path, folder)
                archived += 1
            else:
                os.remove(path)
                deleted += 1
        except OSError as e:
            errors.append(f"{name} : {e.strerror or e}")
    return deleted, archived, errors


# === SYSTÈME DE STYLE UNIFIÉ (design system Socle) ===
CTRL_H = 36  # hauteur commune : boutons, champs de saisie (size-control-lg)
RADIUS = 6  # rayon commun : boutons, champs, panneaux (radius-md)
FONT_BTN = 13  # taille de police des boutons
GAP = 12  # espacement commun entre contrôles (space-3)
# Rôle Socle de chaque couleur historique : (fond, survol, texte, contour)
BTN_COLORS = {
    "orange": ("#fbbf24", "#f59e0b", "#1a1a1a", "#fbbf24"),  # action : l'appel principal
    "green": ("#0369a1", "#075985", "#ffffff", "#0369a1"),  # primary (accent-fill)
    "blue": ("#333333", "#404040", "#ffffff", "#444444"),  # secondaire
    "purple": ("#333333", "#404040", "#ffffff", "#444444"),  # secondaire
    "red": ("#4a1c1c", "#5a2222", "#fecaca", "#ef4444"),  # destructif (danger)
    "neutral": ("#333333", "#404040", "#ffffff", "#444444"),  # secondaire
}


def flat_button(btn: QPushButton, color: str) -> QPushButton:
    """Applique le style de bouton unique de l'application."""
    bg, hover, fg, _ = BTN_COLORS[color]  # Socle plat : aplat sans contour visible
    btn.setFixedHeight(CTRL_H)
    btn.setMinimumWidth(110)
    btn.setCursor(Qt.CursorShape.PointingHandCursor)
    btn.setStyleSheet(
        f"QPushButton {{ background-color: {bg}; color: {fg}; font-size: {FONT_BTN}px; font-weight: 700;"
        f" border: 1px solid {bg}; border-radius: {RADIUS}px; padding: 0 16px; }}"
        f"QPushButton:hover {{ background-color: {hover}; border-color: {hover}; }}"
        f"QPushButton:focus {{ border-color: #38bdf8; }}"
        f"QPushButton:disabled {{ background-color: #333333; color: #666666; border-color: #333333; }}"
    )
    return btn


INPUT_QSS = (
    f"QLineEdit, QComboBox {{ background-color: #2c2c2c; color: #dddddd; border: 1px solid #404040;"
    f" border-radius: {RADIUS}px; padding: 0 12px; min-height: {CTRL_H - 2}px; font-size: 14px; }}"
    f"QLineEdit:focus, QComboBox:focus {{ border: 1px solid #38bdf8; }}"
    # listes déroulantes plates : flèche sans segment ni relief, texte qui s'arrête avant elle
    "QComboBox { padding-right: 28px; }"
    "QComboBox::drop-down, QComboBox::drop-down:editable { subcontrol-origin: padding;"
    " subcontrol-position: center right; width: 24px; border: none; background: transparent; }"
    "QComboBox QLineEdit { background: transparent; border: none; padding: 0; min-height: 0; }"
)

# Style commun des dialogues (fond, champs, boutons standard de QDialogButtonBox)
DIALOG_QSS = (
    "QDialog { background-color: #1e1e1e; color: #dddddd; } QLabel { color: #dddddd; }"
    +INPUT_QSS
    +f"QPushButton {{ background-color: #444444; color: #dddddd; font-size: {FONT_BTN}px; font-weight: 700;"
    f" border: none; border-radius: {RADIUS}px; padding: 0 18px; min-height: {CTRL_H}px; min-width: 110px; }}"
    "QPushButton:hover { background-color: #444444; }"
    "QPushButton:default { background-color: #f59e0b; color: #181818; }"
    "QPushButton:default:hover { background-color: #fbbf24; }"
    f"QListWidget {{ background-color: #2c2c2c; border: 1px solid #404040; border-radius: {RADIUS}px; padding: 5px; }}"
    f"QGroupBox {{ font-weight: 700; border: 1px solid #404040; border-radius: {RADIUS}px; margin-top: 12px; padding: 12px; }}"
    "QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 6px; }"
)


class Worker(QThread):
    """Exécute une fonction bloquante hors du thread UI."""
    result = pyqtSignal(object)
    failed = pyqtSignal(str)

    def __init__(self, fn, parent=None):
        super().__init__(parent)
        self._fn = fn

    def run(self):
        try:
            self.result.emit(self._fn())
        except ai_client.AIError as e:
            self.failed.emit(str(e))
        except Exception as e:  # garde-fou: ne jamais tuer l'UI
            self.failed.emit(L("Erreur inattendue : {e}", e=e))


class SettingsDialog(QDialog):
    """Tous les réglages de l'application, en onglets : Général, Dossiers de logs, IA, Base de connaissances."""

    def __init__(self, settings, folders, parent=None):
        super().__init__(parent)
        self.setWindowTitle(L("Réglages"))
        self.resize(640, 560)
        self.setStyleSheet(DIALOG_QSS)
        self.settings = dict(settings)
        self.temp_folders = {k: list(v) for k, v in folders.items()}
        self._worker = None

        tabs = QTabWidget()
        tabs.setDocumentMode(True)
        tabs.tabBar().setDrawBase(False)  # pas de filet natif clair : seul le filet Socle sous les onglets
        tabs.setStyleSheet("QTabWidget::pane { border: none; border-top: 1px solid #333333; top: -1px; }")
        tabs.addTab(self._general_tab(), L("Général"))
        tabs.addTab(self._folders_tab(), L("Dossiers de logs"))
        tabs.addTab(self._ai_tab(), L("IA"))
        tabs.addTab(self._knowledge_tab(), L("Base de connaissances"))

        self.status = QLabel("")
        self.status.setWordWrap(True)
        self.status.setStyleSheet("color: #f59e0b; font-size: 12px;")

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout = QVBoxLayout(self)
        layout.setSpacing(GAP)
        layout.addWidget(tabs, 1)
        layout.addWidget(self.status)
        layout.addWidget(buttons)
        socle_qt.fit_height(self)  # libellés à la ligne : le dialogue grandit au lieu de rogner

    @staticmethod
    def _form(page):
        form = QFormLayout(page)
        form.setContentsMargins(0, GAP, 0, 0)
        form.setVerticalSpacing(GAP)
        form.setHorizontalSpacing(GAP)
        form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow)
        return form

    @staticmethod
    def _note(text):
        note = QLabel(text)
        note.setWordWrap(True)
        note.setStyleSheet("color: #8f8f8f; font-size: 11px;")
        return note

    # ---- onglets
    def _general_tab(self):
        page = QWidget()
        form = self._form(page)
        self.language = QComboBox()
        self.language.setFixedHeight(CTRL_H)
        for code in i18n.LANGS:
            self.language.addItem(i18n.LANGS[code], code)
        self.language.setCurrentIndex(max(0, self.language.findData(self.settings.get("language", "fr"))))
        form.addRow(L("Langue"), self.language)

        self.game_dir = QLineEdit(self.settings.get("game_dir", ""))
        self.game_dir.setPlaceholderText(L("Auto (CrossOver) — ou dossier contenant SkyrimSE.exe"))
        self.game_dir.setFixedHeight(CTRL_H)
        pick = flat_button(QPushButton(L("Choisir…")), "blue")
        pick.clicked.connect(self._pick_game_dir)
        row = QHBoxLayout()
        row.setSpacing(GAP)
        row.setContentsMargins(0, 0, 0, 0)
        row.addWidget(self.game_dir, 1)
        row.addWidget(pick)
        holder = QWidget()
        holder.setLayout(row)
        form.addRow(L("Dossier du jeu"), holder)

        self.auto_watch = socle_qt.WrapChoice(L("Surveiller les dossiers : nouveau crash = notification + audit automatique"))
        self.auto_watch.setChecked(self.settings.get("auto_watch", "1") == "1")
        form.addRow(L("Surveillance"), self.auto_watch)
        return page

    def _folders_tab(self):
        page = QWidget()
        v = QVBoxLayout(page)
        v.setContentsMargins(0, GAP, 0, 0)
        v.setSpacing(GAP)
        v.addWidget(self._note(L("Dossiers où sKYCRASH cherche les logs de crash, SKSE et Papyrus.") + " "
                               + L("Le dossier SKSE (journal SKSE et rapports de Crash Logger) est toujours analysé, même s'il n'est pas dans la liste.")))
        self.folder_lists = {}
        for game in self.temp_folders:
            lw = QListWidget()
            lw.addItems(self.temp_folders[game])
            self.folder_lists[game] = lw
            v.addWidget(lw, 1)
            add_btn = flat_button(QPushButton(L("Ajouter…")), "neutral")
            add_btn.clicked.connect(lambda _c, g=game: self._add_folder(g))
            rem_btn = flat_button(QPushButton(L("Retirer")), "neutral")
            rem_btn.clicked.connect(lambda _c, g=game: self._remove_folder(g))
            btns = QHBoxLayout()
            btns.setSpacing(GAP)
            btns.addWidget(add_btn)
            btns.addWidget(rem_btn)
            btns.addStretch(1)
            v.addLayout(btns)
        return page

    def _ai_tab(self):
        page = QWidget()
        form = self._form(page)
        self.provider = QComboBox()
        self.provider.addItems(["gemini", "ollama"])
        self.provider.setCurrentText(self.settings.get("provider", "gemini"))
        self.provider.setFixedHeight(CTRL_H)
        self.g_key = QLineEdit()
        self.g_key.setEchoMode(QLineEdit.EchoMode.Password)
        self.g_key.setPlaceholderText(L("(clé enregistrée)") if ai_client.get_api_key() else L("Coller la clé API"))
        self.o_url = QLineEdit(self.settings["ollama_url"])
        # picklists éditables : on peut choisir dans la liste ou saisir un nom de modèle
        self.g_model = self._model_combo(ai_client.FALLBACK_GEMINI_MODELS, self.settings["gemini_model"])
        self.o_model = self._model_combo([], self.settings["ollama_model"])
        for w in (self.provider, self.g_model, self.g_key, self.o_url, self.o_model):
            w.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        form.addRow(L("Fournisseur"), self.provider)
        form.addRow(L("Modèle Gemini"), self._with_refresh(self.g_model, self.refresh_gemini))
        form.addRow(L("Clé API Gemini"), self.g_key)
        form.addRow(L("URL Ollama"), self.o_url)
        form.addRow(L("Modèle Ollama"), self._with_refresh(self.o_model, self.refresh_ollama))
        self.j_key = QLineEdit()
        self.j_key.setEchoMode(QLineEdit.EchoMode.Password)
        self.j_key.setPlaceholderText(L("(clé enregistrée)") if jev_client.get_api_key() else L("Facultatif : clé TypeSafe"))
        self.j_key.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        form.addRow(L("Clé Jev (vérification)"), self.j_key)
        self.use_skills = socle_qt.WrapChoice(L("Utiliser les fiches de connaissances modding Skyrim (dossier skills/)"))
        self.use_skills.setChecked(self.settings.get("use_skills", "1") == "1")
        self.web_search = socle_qt.WrapChoice(L("Recherche web Google (Gemini uniquement, plus lent)"))
        self.web_search.setChecked(self.settings.get("web_search", "0") == "1")
        form.addRow(L("Connaissances"), self.use_skills)
        form.addRow("", self.web_search)
        self.anonymize = socle_qt.WrapChoice(L("Anonymiser les chemins et e-mails avant envoi à Gemini"))
        self.anonymize.setChecked(self.settings.get("anonymize", "1") == "1")
        form.addRow(L("Confidentialité"), self.anonymize)
        form.addRow(self._note(L("La clé est stockée dans le Trousseau macOS (jamais en clair dans la config). ")
                               + L("Avec Gemini, le rapport d'audit et des extraits de logs sont envoyés à Google. Ollama reste 100 % local.") + " "
                               + L("Avec une clé Jev (TypeSafe), chaque conseil de l'assistant est confronté aux faits vérifiés de l'installation, envoyés à TypeSafe ; les conseils contredits sont retirés.")))
        return page

    def _knowledge_tab(self):
        page = QWidget()
        form = self._form(page)
        self.auto_knowledge = socle_qt.WrapChoice(L("Veille automatique : mettre à jour la base de connaissances (GitHub, Steam, Reddit, SKSE)"))
        self.auto_knowledge.setChecked(self.settings.get("auto_knowledge", "1") == "1")
        self.kb_button = flat_button(QPushButton(L("Mettre à jour maintenant")), "blue")
        self.kb_button.clicked.connect(self.refresh_knowledge)
        self.kb_button.setSizePolicy(QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Fixed)
        last = knowledge_updater.status().get("last_run")
        self.kb_status = self._note(L("Dernière mise à jour de la base : {d}",
                                      d=datetime.fromtimestamp(last).strftime("%d/%m/%Y %H:%M") if last else L("jamais")))
        form.addRow(L("Veille"), self.auto_knowledge)
        form.addRow("", self.kb_button)
        form.addRow("", self.kb_status)
        return page

    # ---- dossiers de logs
    def _add_folder(self, game):
        start = str(DOCS / "My Games") if (DOCS / "My Games").is_dir() else str(DOCS)
        path = QFileDialog.getExistingDirectory(self, L("Sélectionner un dossier pour {game}", game=game), start)
        if path and path not in self.temp_folders[game]:
            self.temp_folders[game].append(path)
            self.folder_lists[game].addItem(path)

    def _remove_folder(self, game):
        item = self.folder_lists[game].currentItem()
        if item:
            self.temp_folders[game].remove(item.text())
            self.folder_lists[game].takeItem(self.folder_lists[game].row(item))

    def get_folders(self):
        return self.temp_folders

    # ---- picklists de modèles
    def _pick_game_dir(self):
        d = QFileDialog.getExistingDirectory(self, L("Dossier de Skyrim Special Edition"), self.game_dir.text() or str(HOME))
        if d:
            self.game_dir.setText(d)

    @staticmethod
    def _model_combo(items, current):
        cb = QComboBox()
        cb.setEditable(True)
        cb.setFixedHeight(CTRL_H)
        cb.addItems(items)
        if current and cb.findText(current) < 0:
            cb.insertItem(0, current)
        cb.setCurrentText(current)
        return cb

    def _with_refresh(self, combo, slot):
        btn = flat_button(QPushButton(L("Actualiser")), "blue")
        btn.clicked.connect(slot)
        combo.refresh_button = btn
        row = QHBoxLayout()
        row.setSpacing(GAP)
        row.addWidget(combo, 1)
        row.addWidget(btn)
        holder = QWidget()
        holder.setLayout(row)
        row.setContentsMargins(0, 0, 0, 0)
        return holder

    def _fill(self, combo, models):
        current = combo.currentText()
        combo.clear()
        combo.addItems(models)
        if current and combo.findText(current) < 0:
            combo.insertItem(0, current)  # on garde le choix actuel même s'il n'est plus listé
        combo.setCurrentText(current)

    def _run_refresh(self, combo, fn, label):
        if self._worker is not None and self._worker.isRunning():
            return
        btn = combo.refresh_button
        btn.setEnabled(False)
        self.status.setText(L("Récupération des modèles {label}…", label=label))
        self._worker = Worker(fn, self)

        def done(models):
            btn.setEnabled(True)
            self._fill(combo, models)
            self.status.setText(L("{n} modèle(s) {label} disponible(s).", n=len(models), label=label))

        def fail(msg):
            btn.setEnabled(True)
            self.status.setText(L("Liste indisponible ({msg}). Vous pouvez saisir le nom du modèle.", msg=msg))

        self._worker.result.connect(done)
        self._worker.failed.connect(fail)
        self._worker.start()

    def refresh_knowledge(self):
        if self._worker is not None and self._worker.isRunning():
            return
        self.kb_button.setEnabled(False)
        self.status.setText(L("Mise à jour de la base de connaissances…"))
        self._worker = Worker(lambda: knowledge_updater.update_all(force=True), self)

        def done(rep):
            self.kb_button.setEnabled(True)
            if rep.skipped:
                self.status.setText(L("Mise à jour déjà en cours."))
                return
            self.status.setText(L("Base de connaissances : {u} source(s) mise(s) à jour, {f} en échec.",
                                  u=len(rep.updated), f=len(rep.failed)))

        def fail(msg):
            self.kb_button.setEnabled(True)
            self.status.setText(L("Mise à jour impossible : {msg}", msg=msg))

        self._worker.result.connect(done)
        self._worker.failed.connect(fail)
        self._worker.start()

    def refresh_gemini(self):
        key = self.g_key.text().strip() or None  # utilise la clé saisie, sinon celle du Trousseau
        self._run_refresh(self.g_model, lambda: ai_client.list_gemini_models(key), "Gemini")

    def refresh_ollama(self):
        url = self.o_url.text().strip()
        self._run_refresh(self.o_model, lambda: ai_client.list_ollama_models(url), "Ollama")

    def get_settings(self):
        return {
            "provider": self.provider.currentText(),
            "gemini_model": self.g_model.currentText().strip() or ai_client.DEFAULT_SETTINGS["gemini_model"],
            "ollama_url": self.o_url.text().strip() or ai_client.DEFAULT_SETTINGS["ollama_url"],
            "ollama_model": self.o_model.currentText().strip() or ai_client.DEFAULT_SETTINGS["ollama_model"],
            "use_skills": "1" if self.use_skills.isChecked() else "0",
            "web_search": "1" if self.web_search.isChecked() else "0",
            "auto_watch": "1" if self.auto_watch.isChecked() else "0",
            "auto_knowledge": "1" if self.auto_knowledge.isChecked() else "0",
            "game_dir": self.game_dir.text().strip(),
            "anonymize": "1" if self.anonymize.isChecked() else "0",
            "language": self.language.currentData() or "fr",
        }

    def get_key(self):
        return self.g_key.text().strip()

    def get_jev_key(self):
        return self.j_key.text().strip()


class CrashAnalyzer(QWidget):

    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_NAME)
        self.setFixedSize(1400, 950)
        self.setAutoFillBackground(True)

        self.orange_flat = QColor("#f59e0b")
        self.orange_hover = QColor("#fbbf24")
        self.green_status = QColor("#22c55e")
        self.red_status = QColor("#ef4444")
        self.text_color = QColor("#dddddd")
        self.bg_color = QColor("#1e1e1e")
        self.panel_color = QColor("#2c2c2c")
        self.blue_flat = QColor("#0ea5e9")
        self.purple_flat = QColor("#0ea5e9")

        palette = self.palette()
        palette.setColor(QPalette.ColorRole.Window, self.bg_color)
        palette.setColor(QPalette.ColorRole.WindowText, self.text_color)
        self.setPalette(palette)

        self.audit_report = None
        self.chat_history = []
        self._think_pos = None
        self._think_step = 0
        self._think_timer = QTimer(self)
        self._think_timer.setInterval(350)
        self._think_timer.timeout.connect(self._tick_thinking)
        self._workers = set()
        self.settings = load_settings()
        i18n.set_lang(self.settings["language"])

        left = QWidget()
        main_layout = QVBoxLayout(left)
        main_layout.setContentsMargins(30, 30, 20, 30)
        main_layout.setSpacing(25)

        top = QHBoxLayout()
        top.setSpacing(GAP)

        def make_btn(text, color, slot):
            b = flat_button(QPushButton(text), color)
            b.clicked.connect(slot)
            top.addWidget(b, 1)  # largeurs égales
            return b

        self.analyze_button = make_btn("", "orange", self.analyze_logs)
        self.audit_button = make_btn("", "green", self.run_audit)
        self.select_button = make_btn("", "blue", self.select_log_file)
        self.settings_button = make_btn("", "neutral", self.open_settings)
        main_layout.addLayout(top)

        self.report_box = QTextEdit()
        self.report_box.setReadOnly(True)
        self.report_box.setStyleSheet(
            f"QTextEdit {{ background-color: {self.panel_color.name()}; color: {self.text_color.name()};"
            f" font-family: 'Menlo'; font-size: 13px; border: 1px solid #404040;"
            f" border-radius: {RADIUS}px; padding: 15px; }}"
        )
        main_layout.addWidget(self.report_box)

        self.log_list = QListWidget()
        self.log_list.setMaximumHeight(220)
        self.log_list.setMinimumHeight(120)
        self.log_list.setVerticalScrollMode(QListWidget.ScrollMode.ScrollPerPixel)
        self.log_list.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.log_list.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.log_list.setStyleSheet(
            f"QListWidget {{ background-color: {self.panel_color.name()}; border: 1px solid #404040;"
            f" border-radius: {RADIUS}px; padding: 4px; outline: none; }}"
            "QListWidget::item { border-radius: 6px; }"
            "QListWidget::item:hover { background-color: #333333; }"
            "QListWidget::item:selected { background-color: #404040; }"
        )
        self.log_list.itemActivated.connect(self._open_log_item)
        self.log_list.itemClicked.connect(self._open_log_item)
        main_layout.addWidget(self.log_list)

        self.export_button = flat_button(QPushButton(""), "neutral")
        self.export_button.clicked.connect(self.export_diagnostic)
        self.purge_button = flat_button(QPushButton(""), "red")
        self.purge_button.clicked.connect(self.purge_all_logs)
        bottom = QHBoxLayout()
        bottom.setSpacing(GAP)
        bottom.addWidget(self.export_button, 1)
        bottom.addWidget(self.purge_button, 1)
        main_layout.addLayout(bottom)

        # --- panneau de chat IA ---
        chat_panel = QWidget()
        chat_layout = QVBoxLayout(chat_panel)
        chat_layout.setContentsMargins(20, 30, 30, 30)
        chat_layout.setSpacing(25)  # même rythme vertical que le panneau gauche

        # en-tête : même hauteur que la barre de boutons de gauche -> alignement parfait
        head = QHBoxLayout()
        head.setSpacing(GAP)
        self.chat_title = chat_title = QLabel("")
        chat_title.setFixedHeight(CTRL_H)
        chat_title.setStyleSheet("font-size: 16px; font-weight: 700;")
        head.addWidget(chat_title, 1)
        self.kb_status = QLabel("")
        self.kb_status.setStyleSheet("color: #8f8f8f; font-size: 11px;")
        self.kb_status.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        head.addWidget(self.kb_status)  # à droite du titre, à la place de l'ancien bouton « IA… »

        self.chat_view = QTextEdit()
        self.chat_view.setReadOnly(True)
        self.chat_view.setStyleSheet(
            f"QTextEdit {{ background-color: {self.panel_color.name()}; color: {self.text_color.name()};"
            f" font-size: 13px; border: 1px solid #404040; border-radius: {RADIUS}px; padding: 12px; }}"
        )
        self.chat_view.setMinimumWidth(300)

        self.chat_input = QLineEdit()
        self.chat_input.setStyleSheet(INPUT_QSS)
        self.chat_input.setFixedHeight(CTRL_H)
        self.chat_input.returnPressed.connect(self.send_chat)
        self.send_button = flat_button(QPushButton(""), "green")
        input_row = QHBoxLayout()
        input_row.setSpacing(GAP)
        input_row.addWidget(self.chat_input, 1)
        input_row.addWidget(self.send_button)

        self.explain_button = flat_button(QPushButton(""), "blue")

        self.send_button.clicked.connect(self.send_chat)
        self.explain_button.clicked.connect(self.explain_crash)
        chat_layout.addLayout(head)
        chat_layout.addWidget(self.chat_view, 1)
        chat_layout.addLayout(input_row)
        chat_layout.addWidget(self.explain_button)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.addWidget(left)
        splitter.addWidget(chat_panel)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)
        splitter.setStyleSheet("QSplitter::handle { background: #333333; width: 2px; }")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(splitter)

        # Barre de menus macOS : « Réglages… » (⌘,) rejoint automatiquement le menu sKYCRASH.
        self.menu_bar = QMenuBar(None)
        self.menu_file = self.menu_bar.addMenu("")
        self.act_open = QAction(self)
        self.act_open.setShortcut(QKeySequence.StandardKey.Open)
        self.act_open.triggered.connect(self.select_log_file)
        self.act_settings = QAction(self)
        self.act_settings.setShortcut(QKeySequence("Ctrl+,"))  # ⌘, sur macOS
        self.act_settings.setMenuRole(QAction.MenuRole.PreferencesRole)
        self.act_settings.triggered.connect(self.open_settings)
        self.act_export = QAction(self)
        self.act_export.setShortcut(QKeySequence("Ctrl+E"))  # ⌘E sur macOS
        self.act_export.triggered.connect(self.export_diagnostic)
        self.menu_file.addAction(self.act_open)
        self.menu_file.addAction(self.act_export)
        self.menu_file.addAction(self.act_settings)

        self.game_folders = load_config()
        self._apply_texts()
        self.analyze_logs()

        # surveillance : un nouveau crash log déclenche notification + audit
        self._watcher = QFileSystemWatcher(self)
        self._watch_timer = QTimer(self)
        self._watch_timer.setSingleShot(True)
        self._watch_timer.setInterval(2000)  # laisse le jeu finir d'écrire ses fichiers
        self._watch_timer.timeout.connect(self._on_logs_changed)
        self._watcher.directoryChanged.connect(lambda _p: self._watch_timer.start())
        self._known_crashes = self._crash_names()
        self._known_logs = {p for _n, _f, p, _m in list_logs(self._all_folders())}
        self._setup_watch()
        self.center_window()

        # veille : base de connaissances mise à jour au lancement (si > 1 h), puis toutes les 6 h
        self._kb_timer = QTimer(self)
        self._kb_timer.setInterval(int(knowledge_updater.PERIODIC_INTERVAL_H * 3600 * 1000))
        self._kb_timer.timeout.connect(lambda: self._maybe_update_knowledge(knowledge_updater.PERIODIC_INTERVAL_H))
        self._kb_timer.start()
        self._show_kb_status()
        QTimer.singleShot(2000, lambda: self._maybe_update_knowledge(knowledge_updater.LAUNCH_INTERVAL_H))

    def _maybe_update_knowledge(self, interval_h: float):
        if self.settings.get("auto_knowledge", "1") != "1" or os.environ.get("SKYRIM_CA_FOLDERS"):
            return  # désactivée, ou mode preview (ne rien écrire)
        if not knowledge_updater.due(interval_h):
            return
        self.kb_status.setText(L("Base de connaissances : mise à jour…"))
        self._start(lambda: knowledge_updater.update_all(),
                    lambda rep: self._show_kb_status(rep), lambda _m: self._show_kb_status())

    def _show_kb_status(self, rep=None):
        """Ligne discrète sous le titre du chat : fraîcheur de la base et sources en échec."""
        if self.settings.get("auto_knowledge", "1") != "1":
            self.kb_status.setText(L("Base de connaissances : veille désactivée"))
            return
        last = knowledge_updater.status().get("last_run")
        when = datetime.fromtimestamp(last).strftime("%d/%m %H:%M") if last else L("jamais")
        text = L("Base de connaissances : {n} sources, mise à jour {d}", n=len(knowledge_updater.SOURCES), d=when)
        if rep is not None and rep.failed:
            text += " — " + L("{f} en échec", f=len(rep.failed))
            self.kb_status.setToolTip("\n".join(f"{k} : {v}" for k, v in rep.failed.items()))
        self.kb_status.setText(text)

    def _apply_texts(self):
        """(Re)pose tous les textes statiques dans la langue courante."""
        self.analyze_button.setText(L("Analyser les logs"))
        self.audit_button.setText(L("Audit approfondi"))
        self.select_button.setText(L("Fichier…"))
        self.settings_button.setText(L("Réglages…"))
        self.settings_button.setToolTip(L("Langue, dossiers de logs, IA, base de connaissances (⌘,)"))
        self.menu_file.setTitle(L("Fichier"))
        self.act_open.setText(L("Ouvrir un log…"))
        self.act_settings.setText(L("Réglages…"))
        self.act_export.setText(L("Exporter le diagnostic…"))
        self.export_button.setText(L("Exporter le diagnostic…"))
        self.export_button.setToolTip(L("Un seul fichier avec tout le contexte du plantage, à transmettre (⌘E)"))
        self.purge_button.setText(L("Purger les logs"))
        self.purge_button.setToolTip(L("Supprime les .log / .log0 des répertoires configurés"))
        self.chat_title.setText(L("Assistant IA"))
        self.chat_view.setPlaceholderText(L("Posez une question sur le dernier crash…"))
        self.chat_input.setPlaceholderText(L("Votre question…"))
        if self._think_pos is None:
            self.send_button.setText(L("Envoyer"))
        self.explain_button.setText(L("Expliquer le crash"))

    # ------------------------------------------------------------ audit / IA
    def _all_folders(self):
        return [f for folders in with_skse_dir(self.game_folders).values() for f in folders]

    # ------------------------------------------------------------ surveillance
    def _crash_names(self) -> set:
        return {p for n, _f, p, _m in list_logs(self._all_folders())
                if re.match(r"(crash[-_]|.*netscriptframework)", n, re.I)}

    def _setup_watch(self):
        old = self._watcher.directories()
        if old:
            self._watcher.removePaths(old)
        if self.settings.get("auto_watch", "1") == "1":
            dirs = [f for f in self._all_folders() if os.path.isdir(f)]
            if dirs:
                self._watcher.addPaths(dirs)

    def _on_logs_changed(self):
        current = self._crash_names()
        new = current - self._known_crashes
        self._known_crashes = current
        all_now = {p for _n, _f, p, _m in list_logs(self._all_folders())}
        if all_now == self._known_logs and not new:
            return  # simple réécriture d'un log existant : on garde le rapport affiché
        self._known_logs = all_now
        self.analyze_logs()
        if not new:
            return
        name = os.path.basename(sorted(new)[-1])
        self._notify(APP_NAME, L("Nouveau crash détecté : {name}", name=name))
        if self.audit_button.isEnabled():
            self.run_audit()

    @staticmethod
    def _notify(title: str, message: str) -> None:
        """Notification macOS (osascript). Silencieux en cas d'échec."""
        if sys.platform != "darwin":
            return

        def esc(s: str) -> str:
            return s.replace("\\", "\\\\").replace('"', '\\"')

        try:
            subprocess.run(
                ["osascript", "-e", f'display notification "{esc(message)}" with title "{esc(title)}"'],
                timeout=5, check=False, capture_output=True)
        except (OSError, subprocess.SubprocessError):
            pass

    def _start(self, fn, on_result, on_fail):
        w = Worker(fn, self)
        self._workers.add(w)
        w.result.connect(on_result)
        w.failed.connect(on_fail)
        w.finished.connect(lambda: self._workers.discard(w))
        w.start()

    def run_audit(self):
        files = gather_audit_files(self._all_folders())
        if not files:
            self.report_box.setText(L("Aucun log à auditer. Configurez les dossiers dans Réglages… > Dossiers de logs."))
            return
        self.audit_button.setEnabled(False)
        self.report_box.setText(L("Audit en cours…"))
        game_dir = self.settings.get("game_dir", "")
        self._start(lambda: audit_engine.audit_paths(files, game_dir), self._on_audit_done, self._on_audit_failed)

    def export_diagnostic(self):
        files = gather_audit_files(self._all_folders())
        if not files:
            QMessageBox.information(self, APP_NAME, L("Aucun log à exporter. Configurez les dossiers dans Réglages… > Dossiers de logs."))
            return
        start = HOME / "Desktop" if (HOME / "Desktop").is_dir() else HOME
        path, _ = QFileDialog.getSaveFileName(self, L("Exporter le diagnostic"), str(start / diagnostic.default_filename()),
                                              L("Markdown (*.md)"))
        if not path:
            return
        self.export_button.setEnabled(False)
        game_dir = self.settings.get("game_dir", "")
        anon = self.settings.get("anonymize", "1") == "1"

        def work():
            report = audit_engine.audit_paths(files, game_dir)
            with open(path, "w", encoding="utf-8") as f:
                f.write(diagnostic.build(report, audit_engine.read_lines, anonymize=anon, app_name=APP_NAME))
            return report

        def done(report):
            self.export_button.setEnabled(True)
            self.audit_report = report
            self.render_audit(report)
            self._offer_game_dir(report)
            subprocess.run(["open", "-R", path], check=False)  # le fichier apparaît sélectionné dans le Finder

        def fail(msg):
            self.export_button.setEnabled(True)
            QMessageBox.warning(self, APP_NAME, L("Export impossible : {msg}", msg=msg))

        self._start(work, done, fail)

    def _on_audit_done(self, report):
        self.audit_button.setEnabled(True)
        self.audit_report = report
        self.render_audit(report)
        self._offer_game_dir(report)

    def _offer_game_dir(self, report):
        """Le dossier du jeu des réglages n'existe plus mais l'installation a été retrouvée : proposer de l'adopter."""
        found = report.extras.get("game_dir_found")
        old = self.settings.get("game_dir", "")
        if not found or not old or found == getattr(self, "_game_dir_declined", None):
            return
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Question)
        box.setWindowTitle(L("Dossier du jeu"))
        box.setText(L("Le dossier du jeu des réglages n'existe plus. Utiliser l'installation retrouvée ?"))
        box.setInformativeText(L("Ancien : {old}\nRetrouvé : {new}", old=old, new=found))
        use = box.addButton(L("Utiliser ce dossier"), QMessageBox.ButtonRole.AcceptRole)
        box.addButton(L("Plus tard"), QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if box.clickedButton() is use:
            self.settings["game_dir"] = found
            save_settings(self.settings)
        else:
            self._game_dir_declined = found  # ne pas redemander pendant cette session

    def _on_audit_failed(self, msg):
        self.audit_button.setEnabled(True)
        self.report_box.setText(L("Échec de l'audit : {msg}", msg=msg))

    def render_audit(self, report):
        self.report_box.clear()
        cur = self.report_box.textCursor()
        cur.insertText(L("AUDIT — {verdict}", verdict=report.verdict) + "\n", self.format_text(self.orange_flat, bold=True))
        install = (L("Installation : {dir}", dir=report.game_dir) if report.game_dir else
                   L("Installation non localisée — indiquez le dossier du jeu dans Réglages… > Général pour activer les contrôles de version."))
        cur.insertText(f"{install}\n\n", self.format_text(QColor('#8f8f8f')))
        if report.suspects:
            cur.insertText(L("Suspects classés") + "\n", self.format_text(self.text_color, bold=True))
            for i, (name, score, reasons) in enumerate(report.suspects, 1):
                cur.insertText(f"  {i}. {name} ", self.format_text(self.red_status if i == 1 else self.text_color))
                cur.insertText(L("(score {score}) ", score=score) + f"{reasons[0] if reasons else ''}\n", self.format_text(QColor('#8f8f8f')))
            cur.insertText("\n")
        colors = {audit_engine.SEV_CRIT: self.red_status, audit_engine.SEV_WARN: self.orange_flat,
                  audit_engine.SEV_INFO: self.green_status}
        for f in sorted(report.findings, key=lambda x:-x.severity):
            cur.insertText(f"[{audit_engine.sev_label(f.severity)}] ", self.format_text(colors[f.severity], bold=True))
            cur.insertText(f"{f.title} — {f.source}\n", self.format_text(self.text_color))
            if f.detail:
                cur.insertText(f"    {f.detail}\n", self.format_text(QColor('#aaaaaa')))
            for e in f.evidence[:2]:
                cur.insertText(f"    > {e[:200]}\n", self.format_text(QColor('#8f8f8f')))
            if f.suggestion:
                cur.insertText("    " + L("Piste : {s}", s=f.suggestion) + "\n", self.format_text(self.blue_flat))
        self.report_box.moveCursor(self.report_box.textCursor().MoveOperation.Start)

    def open_settings(self):
        dlg = SettingsDialog(self.settings, self.game_folders, self)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        old_lang = self.settings.get("language")
        self.settings = dlg.get_settings()
        save_settings(self.settings)
        i18n.set_lang(self.settings["language"])
        self._apply_texts()
        folders = dlg.get_folders()
        folders_changed = folders != self.game_folders
        if folders_changed:
            self.game_folders = folders
            save_config(self.game_folders)
            self._known_crashes = self._crash_names()
        self._setup_watch()
        if folders_changed or self.settings["language"] != old_lang:
            self.analyze_logs()
            if self.audit_report is not None:
                self.audit_report = None
                self.run_audit()
        key = dlg.get_key()
        if key:
            try:
                ai_client.set_api_key(key)
            except ai_client.AIError as e:
                QMessageBox.warning(self, APP_NAME, str(e))
        jkey = dlg.get_jev_key()
        if jkey:
            try:
                jev_client.set_api_key(jkey)
            except jev_client.JevError as e:
                QMessageBox.warning(self, APP_NAME, str(e))

    def explain_crash(self):
        self.chat_input.setText(
            L("Quelle est la cause la plus probable du dernier crash ? Que dois-je vérifier en premier ?"))
        self.send_chat()

    def _append_chat(self, who, text, color):
        cur = self.chat_view.textCursor()
        cur.movePosition(cur.MoveOperation.End)
        cur.insertText(f"{L(who)}\n", self.format_text(color, bold=True))
        if who == "Assistant":
            cur.insertHtml(ai_format.render_html(text))
            cur.insertText("\n", self.format_text(self.text_color))
        else:
            cur.insertText(f"{text}\n\n", self.format_text(self.text_color))
        self.chat_view.setTextCursor(cur)
        self.chat_view.ensureCursorVisible()

    def send_chat(self):
        question = self.chat_input.text().strip()
        if not question or not self.send_button.isEnabled():
            return
        self.chat_input.clear()
        self._append_chat(N_("Vous"), question, self.blue_flat)
        self.chat_history.append({"role": "user", "content": question})
        history = self.chat_history[-12:]
        settings = dict(self.settings)
        existing = self.audit_report
        files = gather_audit_files(self._all_folders())
        self.send_button.setEnabled(False)
        self.explain_button.setEnabled(False)
        self.send_button.setText("●  ")
        self._start_thinking()

        def job():
            report = existing or audit_engine.audit_paths(files, settings.get("game_dir", ""))
            answer = ai_client.chat(settings, report.to_context(), history)
            answer, _removed = guard.apply(answer, report.extras.get("inventory") or {},
                                     guard.default_judge())  # filet de sécurité (motifs + Jev si clé)
            return report, answer

        self._start(job, self._on_chat_done, self._on_chat_failed)

    def _start_thinking(self):
        cur = self.chat_view.textCursor()
        cur.movePosition(cur.MoveOperation.End)
        self._think_pos = cur.position()
        self._think_step = 0
        self._tick_thinking()
        self._think_timer.start()

    def _tick_thinking(self):
        if self._think_pos is None:
            return
        dots = "." * (self._think_step % 3 + 1)
        self._think_step += 1
        cur = self.chat_view.textCursor()
        cur.setPosition(self._think_pos)
        cur.movePosition(cur.MoveOperation.End, cur.MoveMode.KeepAnchor)
        cur.removeSelectedText()
        cur.insertText(L("Assistant réfléchit") + f" {dots}\n\n", self.format_text(QColor('#8f8f8f')))
        self.chat_view.setTextCursor(cur)
        self.chat_view.ensureCursorVisible()
        self.send_button.setText("●" * (self._think_step % 3 + 1))

    def _stop_thinking(self):
        self._think_timer.stop()
        if self._think_pos is not None:
            cur = self.chat_view.textCursor()
            cur.setPosition(self._think_pos)
            cur.movePosition(cur.MoveOperation.End, cur.MoveMode.KeepAnchor)
            cur.removeSelectedText()
            self.chat_view.setTextCursor(cur)
            self._think_pos = None

    def _chat_ready(self):
        self._stop_thinking()
        self.send_button.setEnabled(True)
        self.explain_button.setEnabled(True)
        self.send_button.setText(L("Envoyer"))

    def _on_chat_done(self, payload):
        self._stop_thinking()
        report, answer = payload
        if self.audit_report is None:
            self.audit_report = report
            self.render_audit(report)
        self.chat_history.append({"role": "assistant", "content": answer})
        self._append_chat(N_("Assistant"), answer, self.orange_flat)
        self._chat_ready()

    def _on_chat_failed(self, msg):
        self._stop_thinking()
        if self.chat_history and self.chat_history[-1]["role"] == "user":
            self.chat_history.pop()
        self._append_chat(N_("Erreur"), msg, self.red_status)
        self._chat_ready()

    def center_window(self):
        screen = QApplication.primaryScreen()
        if screen:
            g = screen.availableGeometry()
            self.move(g.x() + (g.width() - self.width()) // 2,
                      g.y() + (g.height() - self.height()) // 2)

    def select_log_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, L("Ouvrir Log"), str(DOCS if DOCS.is_dir() else HOME), L("Logs (*.log *.txt)")
        )
        if not path:
            return
        if not os.path.isfile(path):
            QMessageBox.warning(self, APP_NAME, L("Fichier introuvable."))
            return
        err = scan_for_errors(path)
        self.report_box.clear()
        cur = self.report_box.textCursor()
        name = os.path.basename(path)
        if err:
            cur.insertText(f"• {name} : ", self.format_text(self.text_color))
            cur.insertText(f"{err}\n", self.format_text(self.red_status))
        else:
            cur.insertText("✅ " + L("Aucun problème détecté dans {name}.", name=name), self.format_text(self.green_status))

    def purge_all_logs(self):
        """Supprime les .log/.log0 des répertoires configurés, après confirmation."""
        folders = self._all_folders()
        logs = list_logs(folders)
        if not logs:
            QMessageBox.information(self, APP_NAME, L("Aucun fichier log à supprimer."))
            return
        dirs = sorted({f for _n, f, _p, _m in logs})
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Warning)
        box.setWindowTitle(L("Purger les logs"))
        crashes = sum(1 for n, _f, _p, _m in logs if CRASH_NAME_RE.match(n))
        box.setText(L("Supprimer définitivement {n} fichier(s) log ?", n=len(logs) - crashes))
        box.setInformativeText(
            L("Dossiers concernés :") + "\n" + "\n".join(dirs) + "\n\n"
            + (L("Les {k} rapport(s) de plantage sont archivés dans « {dir} » : l'historique les garde.",
                 k=crashes, dir=insights.ARCHIVE_DIR) + "\n" if crashes else "")
            + L("Les autres logs sont supprimés : action irréversible."))
        yes = box.addButton(L("Supprimer"), QMessageBox.ButtonRole.DestructiveRole)
        box.addButton(L("Annuler"), QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if box.clickedButton() is not yes:
            return
        deleted, archived, errors = purge_logs(folders)
        self.analyze_logs()
        self._known_crashes = self._crash_names()
        msg = L("{n} fichier(s) supprimé(s).", n=deleted)
        if archived:
            msg += " " + L("{n} rapport(s) de plantage archivé(s).", n=archived)
        if errors:
            QMessageBox.warning(self, APP_NAME, msg + "\n\n" + L("Échecs :") + "\n" + "\n".join(errors[:10]))
        else:
            QMessageBox.information(self, APP_NAME, msg)

    def analyze_logs(self):
        self.report_box.clear()
        cursor = self.report_box.textCursor()
        results = {}  # chemin complet -> bool erreur
        any_folder = False

        for game, folders in with_skse_dir(self.game_folders).items():
            game_errors = []
            for name, folder, path, _m in list_logs(folders):
                any_folder = True
                err = scan_for_errors(path)
                results[path] = bool(err)
                if err:
                    game_errors.append((name, err, os.path.basename(folder)))

            cursor.insertText(f"● {game}\n", self.format_text(self.orange_flat, bold=True))
            if not game_errors:
                cursor.insertText("  ✅ " + L("Aucun problème détecté.") + "\n\n", self.format_text(self.green_status))
            else:
                for name, msg, folder in game_errors:
                    cursor.insertText(f"  • [{folder}] {name} : ", self.format_text(self.text_color))
                    cursor.insertText(f"{msg}\n", self.format_text(self.red_status))
                cursor.insertText("\n")

        if not any_folder:
            cursor.insertText(
                L("Aucun fichier .log trouvé. Configurez les dossiers dans Réglages… > Dossiers de logs.") + "\n",
                self.format_text(self.text_color),
            )
        self.refresh_grid(results)

    def refresh_grid(self, results):
        """Liste compacte (une ligne par log, plus récent en premier), cliquable."""
        self.log_list.clear()

        all_logs = []
        for game, folders in with_skse_dir(self.game_folders).items():
            for name, folder, path, mtime in list_logs(folders):
                all_logs.append((name, folder, path, mtime, game))
        all_logs.sort(key=lambda x: x[3], reverse=True)

        for name, folder, path, mtime, game in all_logs[:MAX_CARDS]:
            is_err = results.get(path, False)
            try:
                when = datetime.fromtimestamp(mtime).strftime("%d/%m %H:%M")
            except (OSError, OverflowError, ValueError):
                when = "—"

            row = QWidget()
            row.setStyleSheet("background: transparent;")
            lay = QHBoxLayout(row)
            lay.setContentsMargins(10, 0, 10, 0)
            lay.setSpacing(10)

            dot = QLabel("●")
            dot.setFixedWidth(14)
            dot.setStyleSheet(f"color: {'#ef4444' if is_err else '#22c55e'}; font-size: 12px;")
            title = QLabel(name)
            title.setStyleSheet("color: white; font-size: 13px; font-weight: 700;")
            title.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
            meta = QLabel(f"{game} · {os.path.basename(folder)} · {when}")
            meta.setStyleSheet("color: #8f8f8f; font-size: 11px;")
            meta.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            lay.addWidget(dot)
            lay.addWidget(title, 1)
            lay.addWidget(meta)

            item = QListWidgetItem()
            item.setData(Qt.ItemDataRole.UserRole, (path, name))
            item.setToolTip(path)
            item.setSizeHint(QSize(0, 36))
            self.log_list.addItem(item)
            self.log_list.setItemWidget(item, row)

    def _open_log_item(self, item):
        data = item.data(Qt.ItemDataRole.UserRole)
        if data:
            self.show_log_content(*data)

    def show_log_content(self, filepath, filename):
        dialog = QDialog(self)
        dialog.setWindowTitle(L("Lecture : {name}", name=filename))
        dialog.resize(900, 650)
        dialog.setStyleSheet(f"background-color: {self.bg_color.name()}; color: {self.text_color.name()};")
        layout = QVBoxLayout(dialog)
        area = QTextEdit()
        area.setReadOnly(True)
        area.setStyleSheet(
            "QTextEdit { background-color: #1a1a1a; color: #dddddd; font-family: 'Menlo';"
            " font-size: 13px; border: 1px solid #333333; padding: 10px; }"
        )
        area.setPlainText("\n".join(read_lines(filepath)))
        layout.addWidget(area)
        dialog.exec()

    @staticmethod
    def format_text(color, bold=False):
        fmt = QTextCharFormat()
        fmt.setForeground(color)
        if bold:
            fmt.setFontWeight(800)
        return fmt


def main():
    app = QApplication(sys.argv)
    socle_qt.apply(app, full=False)  # design system Socle
    app.setApplicationName(APP_NAME)
    win = CrashAnalyzer()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
