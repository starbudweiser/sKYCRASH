"""Écran de lancement animé (règle Socle « Splash animé », modèle : le splash de mORTEX).

Fenêtre sans cadre et transparente de 500 × 190 px (carte de 476 × 166 et marge de 12 px pour
son ombre), centrée. Chronologie : t = 0 splash visible → t = 2 s fenêtre principale → t = 4 s
sortie animée de 600 ms. Si la fenêtre principale n'est pas prête à 4 s, le splash attend
qu'elle soit affichée. Réglage « Réduire les animations » de macOS : splash fixe, mêmes durées.

Tout est dessiné au QPainter (PyQt6 sans WebEngine) ; le logo reprend l'œil de l'icône.
Sobriété Socle : carte plate, seules l'entrée du nom et de l'icône, le filet et le sous-titre s'animent.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import sys

from PyQt6.QtCore import QElapsedTimer, QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import (
    QColor, QFont, QFontMetricsF, QGuiApplication, QPainter, QPainterPath, QPen, QTransform,
)
from PyQt6.QtWidgets import QWidget

import socle_qt
from i18n import L, N_

WIDTH = socle_qt.TOKENS["metrics"]["size-splash-width"]    # 500 : carte de 476 et marge de 12
HEIGHT = socle_qt.TOKENS["metrics"]["size-splash-height"]  # 190 : carte de 166 et marge de 12
MARGIN = 12
SHOWN_MS = 4000      # durée à l'écran avant la sortie
MAIN_AT_MS = 2000    # ouverture de la fenêtre principale
LEAVE_MS = 600       # sortie animée

ORANGE = QColor("#ff7a00")    # orange de l'iris de l'icône
PAD = socle_qt.TOKENS["metrics"]["space-6"]              # marge intérieure, identique à gauche et à droite
TITLE_PX = socle_qt.TOKENS["metrics"]["size-splash-title"]  # taille fixe du nom, la même dans toutes les applis
LOGO, GAP = 108, 26
SUB_SPACING = 5

SUBTITLE = N_("ANALYSE DE CRASH")


def reduce_motion() -> bool:
    """Réglage d'accessibilité macOS « Réduire les animations » (équivalent de prefers-reduced-motion)."""
    if sys.platform != "darwin":
        return False
    try:
        objc = ctypes.cdll.LoadLibrary(ctypes.util.find_library("objc"))
        objc.objc_getClass.restype = ctypes.c_void_p
        objc.sel_registerName.restype = ctypes.c_void_p
        send = objc.objc_msgSend
        send.restype = ctypes.c_void_p
        send.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        ws = send(objc.objc_getClass(b"NSWorkspace"), objc.sel_registerName(b"sharedWorkspace"))
        send.restype = ctypes.c_bool
        return bool(send(ws, objc.sel_registerName(b"accessibilityDisplayShouldReduceMotion")))
    except Exception:  # noqa: BLE001 — sans accès au réglage, animations normales
        return False


# ---------------------------------------------------------------- courbes d'animation

def _bezier(x1: float, y1: float, x2: float, y2: float):
    """Équivalent de cubic-bezier() CSS : renvoie f(t) pour t dans [0, 1]."""
    def coord(t, a, b):
        return 3 * a * t * (1 - t) ** 2 + 3 * b * t * t * (1 - t) + t ** 3

    def f(x: float) -> float:
        if x <= 0:
            return 0.0
        if x >= 1:
            return 1.0
        lo, hi = 0.0, 1.0
        for _ in range(30):
            mid = (lo + hi) / 2
            if coord(mid, x1, x2) < x:
                lo = mid
            else:
                hi = mid
        return coord((lo + hi) / 2, y1, y2)
    return f


EASE_CARD = _bezier(0.16, 1, 0.3, 1)
EASE_IRIS = _bezier(0.22, 1, 0.36, 1)
EASE_WHITE = _bezier(0.34, 1.3, 0.5, 1)
EASE_LETTER = _bezier(0.2, 1.2, 0.4, 1)
EASE_RULE = _bezier(0.65, 0, 0.35, 1)
EASE_LEAVE = _bezier(0.6, -0.28, 0.735, 0.045)  # easeInBack : la carte gonfle puis se replie


def _phase(t: float, start: float, dur: float) -> float:
    """Avancement de 0 à 1 d'une animation qui commence à `start` ms et dure `dur` ms."""
    return min(1.0, max(0.0, (t - start) / dur))


def _lerp(a: float, b: float, k: float) -> float:
    return a + (b - a) * k



# ---------------------------------------------------------------- logo : l'œil de l'icône

def _eye_white() -> QPainterPath:
    """Blanc de l'œil, dans le repère 1024 × 1024 de l'icône."""
    disc = QPainterPath()
    disc.addEllipse(QPointF(509, 523), 262, 262)
    lid = QPainterPath()
    lid.moveTo(240, 352)
    lid.cubicTo(380, 278, 560, 288, 640, 372)
    lid.cubicTo(690, 422, 720, 470, 776, 472)
    lid.lineTo(800, 800)
    lid.lineTo(220, 800)
    lid.closeSubpath()
    return disc.intersected(lid)


EYE_WHITE = _eye_white()
EYE_CENTER = QPointF(509, 523)
IRIS_CENTER = QPointF(510, 473)


class SplashScreen(QWidget):
    """Splash de lancement : appeler start(open_main), qui ouvre la fenêtre principale à 2 s."""

    def __init__(self):
        # fenêtre ordinaire : Qt.Tool et Qt.SplashScreen donnent sous macOS un panneau qui se
        # masque dès que l'appli n'est plus active
        super().__init__(None, Qt.WindowType.Window | Qt.WindowType.FramelessWindowHint
                         | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.NoDropShadowWindowHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setFixedSize(WIDTH, HEIGHT)
        self.static = reduce_motion()
        self.title = "sKYCRASH"
        self.subtitle = L(SUBTITLE)
        self._clock = QElapsedTimer()
        self._leave_at: float | None = None
        self._main_shown = False
        self._long_enough = False
        self._open_main = None
        self._tick = QTimer(self)
        self._tick.setTimerType(Qt.TimerType.PreciseTimer)
        self._tick.setInterval(16)
        self._tick.timeout.connect(self.update)

        base = QGuiApplication.font().family()
        self.f_title = QFont(base)
        self.f_title.setPixelSize(TITLE_PX)
        self.f_title.setWeight(QFont.Weight.ExtraBold)
        self.f_title.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.5)
        self.f_sub = QFont(base)
        self.f_sub.setPixelSize(17)
        self.f_sub.setWeight(QFont.Weight.DemiBold)
        self.f_sub_final = QFont(self.f_sub)
        self.f_sub_final.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, SUB_SPACING)

    # ------------------------------------------------------------ chronologie

    def start(self, open_main) -> None:
        """Affiche le splash ; `open_main()` crée et affiche la fenêtre principale à t = 2 s."""
        self._open_main = open_main
        screen = QGuiApplication.primaryScreen().availableGeometry()
        self.move(screen.center().x() - WIDTH // 2, screen.center().y() - HEIGHT // 2)
        self.show()
        self._clock.start()
        if not self.static:
            self._tick.start()
        # minuteries précises : les minuteries par défaut peuvent se déclencher 5 % trop tôt
        QTimer.singleShot(MAIN_AT_MS, Qt.TimerType.PreciseTimer, self._show_main)
        QTimer.singleShot(SHOWN_MS, Qt.TimerType.PreciseTimer, self._shown_long_enough)

    def elapsed(self) -> float:
        return float(self._clock.elapsed()) if self._clock.isValid() else 0.0

    def _show_main(self) -> None:
        self._open_main()
        self._main_shown = True
        # pas de raise_() : sous macOS il sort le splash de l'écran tant que l'appli n'est pas
        # active ; WindowStaysOnTopHint le garde au-dessus de la fenêtre principale
        self._maybe_leave()

    def _shown_long_enough(self) -> None:
        self._long_enough = True
        self._maybe_leave()

    def _maybe_leave(self) -> None:
        """Sortie à 4 s, ou dès que la fenêtre principale est affichée si elle a pris du retard."""
        if self._leave_at is not None or not self._main_shown or not self._long_enough:
            return
        self._leave_at = self.elapsed()
        if self.static:
            self.hide()  # pas d'animation de sortie, mais mêmes durées
        QTimer.singleShot(LEAVE_MS + 50, Qt.TimerType.PreciseTimer, self.close)

    # ------------------------------------------------------------ dessin

    def paintEvent(self, _event) -> None:  # noqa: N802 (API Qt)
        t = 3000.0 if self.static else self.elapsed()  # image fixe : tout est en place
        p = QPainter(self)
        p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.TextAntialiasing)
        card = QRectF(MARGIN, MARGIN, WIDTH - 2 * MARGIN, HEIGHT - 2 * MARGIN)
        cx, cy = card.center().x(), card.center().y()

        opacity = min(1.0, _phase(t, 0, 300))
        if self._leave_at is not None and not self.static:
            k = _phase(self.elapsed(), self._leave_at, LEAVE_MS)
            s = _lerp(1, 0.05, EASE_LEAVE(k))
            p.translate(cx, cy)
            p.scale(s, s)
            p.translate(-cx, -cy)
            opacity *= 1.0 if k < 0.7 else 1 - (k - 0.7) / 0.3
        p.setOpacity(max(0.0, opacity))

        # Carte plate (Socle) : ni ombre, ni dégradé, ni reflet
        p.setPen(QPen(QColor(socle_qt.c("border-strong", "dark")), 1))
        p.setBrush(QColor(socle_qt.c("surface-raised", "dark")))
        p.drawRoundedRect(card.adjusted(0.5, 0.5, -0.5, -0.5), 16, 16)

        # Contenu centré entre deux marges identiques (space-6)
        avail = card.width() - 2 * PAD - LOGO - GAP
        title_w = sum(QFontMetricsF(self.f_title).horizontalAdvance(ch) + 0.5 for ch in self.title)
        sub_w = QFontMetricsF(self.f_sub_final).horizontalAdvance(self.subtitle) - SUB_SPACING
        sub_fit = min(1.0, avail / max(1.0, sub_w))
        text_w = max(title_w, sub_w * sub_fit)
        left = card.left() + PAD + (card.width() - 2 * PAD - (LOGO + GAP + text_w)) / 2
        self._paint_logo(p, QPointF(left + LOGO / 2, cy), t)
        self._paint_text(p, QPointF(left + LOGO + GAP, cy), text_w, sub_fit, t)
        p.end()

    def _paint_logo(self, p: QPainter, center: QPointF, t: float) -> None:
        """L'œil de l'icône : le blanc se pose avec rebond, l'iris arrive en tourbillon."""
        p.save()
        p.translate(center)
        p.scale(LOGO / 524, LOGO / 524)  # l'œil (524 unités de large) occupe toute la largeur LOGO
        p.translate(-EYE_CENTER.x(), -EYE_CENTER.y() + 26)

        sw = _lerp(0.3, 1, EASE_WHITE(_phase(t, 150, 1500)))
        p.translate(EYE_CENTER)
        p.scale(sw, sw)
        p.translate(-EYE_CENTER)
        p.setOpacity(p.opacity() * _phase(t, 150, 450))
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor("#ffffff"))
        p.drawPath(EYE_WHITE)

        p.setClipPath(EYE_WHITE, Qt.ClipOperation.IntersectClip)
        ki = _phase(t, 0, 1300)
        e = EASE_IRIS(ki)
        p.setOpacity(p.opacity() * min(1.0, ki / 0.4))
        p.translate(IRIS_CENTER)
        p.scale(_lerp(0.2, 1, e), _lerp(0.2, 1, e))
        p.rotate(_lerp(-420, 0, e))
        p.setBrush(ORANGE)
        p.drawEllipse(QPointF(0, 0), 162, 162)
        p.setBrush(QColor("#1f1208"))
        p.drawEllipse(QPointF(0, 0), 102, 102)
        p.setBrush(QColor("#ffffff"))
        p.drawEllipse(QPointF(90, -48), 30, 30)
        p.drawEllipse(QPointF(61, -90), 13, 13)
        p.restore()

    def _paint_text(self, p: QPainter, origin: QPointF, text_w: float, sub_fit: float, t: float) -> None:
        left = origin.x()
        size = float(TITLE_PX)
        fm = QFontMetricsF(self.f_title)
        sub_h, rule_gap = 17 * 1.25, 10 + 2 + 9
        top = origin.y() - (size + rule_gap + sub_h) / 2
        base = top + fm.ascent() - (fm.ascent() + fm.descent() - size) / 2

        # Nom : lettres qui basculent une à une (taille fixe size-splash-title)
        p.save()
        p.setFont(self.f_title)
        x = left
        for i, ch in enumerate(self.title):
            w = fm.horizontalAdvance(ch) + 0.5
            k = _phase(t, 450 + i * 70, 700)
            if k > 0:
                e = EASE_LETTER(k)
                oy = top + size * 0.85
                tr = QTransform()
                tr.translate(x + w / 2, oy + _lerp(14, 0, e))
                tr.rotate(_lerp(-95, 0, e), Qt.Axis.XAxis)
                tr.translate(-(x + w / 2), -oy)
                p.save()
                p.setTransform(tr, True)
                p.setOpacity(p.opacity() * min(1.0, k * 1.6))
                p.setPen(ORANGE if i == 0 else QColor("#ffffff"))
                p.drawText(QPointF(x, base), ch)
                p.restore()
            x += w
        p.restore()

        # Filet orange
        k = EASE_RULE(_phase(t, 950, 700))
        if k > 0:
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(ORANGE)
            p.drawRect(QRectF(left, top + size + 10, text_w * k, 2))

        # Sous-titre : l'espacement se resserre ; réduit au besoin pour tenir dans la zone utile
        k = _phase(t, 1100, 900)
        if k > 0:
            e = EASE_CARD(k)
            f = QFont(self.f_sub)
            spacing = _lerp(14, SUB_SPACING, e)
            f.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, spacing)
            width = QFontMetricsF(f).horizontalAdvance(self.subtitle)
            p.save()
            p.setFont(f)
            p.setPen(QColor("#d8d8d8"))
            p.setOpacity(p.opacity() * e)
            p.translate(left, top + size + rule_gap)
            p.scale(sub_fit, sub_fit)
            p.setClipRect(QRectF(0, -4, text_w / sub_fit + 2, sub_h + 8))
            p.drawText(QRectF(0, 0, width + 40, sub_h),
                       Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, self.subtitle)
            p.restore()
