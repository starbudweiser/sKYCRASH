"""Écran de lancement animé (règle Socle « Splash animé », modèle : le splash de mORTEX).

Fenêtre sans cadre et transparente de 500 × 190 px (carte de 476 × 166 et marge de 12 px pour
son ombre), centrée. Chronologie : t = 0 splash visible → t = 2 s fenêtre principale → t = 4 s
sortie animée de 600 ms. Si la fenêtre principale n'est pas prête à 4 s, le splash attend
qu'elle soit affichée. Réglage « Réduire les animations » de macOS : splash fixe, mêmes durées.

Tout est dessiné au QPainter (PyQt6 sans WebEngine) ; le logo reprend l'œil de l'icône.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import math
import sys

from PyQt6.QtCore import QElapsedTimer, QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import (
    QBrush, QColor, QConicalGradient, QFont, QFontMetricsF, QGuiApplication, QLinearGradient, QPainter,
    QPainterPath, QPen, QRadialGradient, QTransform,
)
from PyQt6.QtWidgets import QWidget

from i18n import L, N_

WIDTH, HEIGHT, MARGIN = 500, 190, 12  # tokens Socle size-splash-width / size-splash-height
SHOWN_MS = 4000      # durée à l'écran avant la sortie
MAIN_AT_MS = 2000    # ouverture de la fenêtre principale
LEAVE_MS = 600       # sortie animée

ORANGE_1 = QColor("#ffc15a")
ORANGE_2 = QColor("#ff5e0a")

SUBTITLE = N_("ANALYSE DE CRASH")
FOOTER = N_("Logs · audit · assistant IA")


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
EASE_INOUT = _bezier(0.42, 0, 0.58, 1)
EASE_LEAVE = _bezier(0.6, -0.28, 0.735, 0.045)  # easeInBack : la carte gonfle puis se replie


def _phase(t: float, start: float, dur: float) -> float:
    """Avancement de 0 à 1 d'une animation qui commence à `start` ms et dure `dur` ms."""
    return min(1.0, max(0.0, (t - start) / dur))


def _lerp(a: float, b: float, k: float) -> float:
    return a + (b - a) * k


def _heartbeat(k: float) -> float:
    """Double pulsation puis repos (mêmes paliers que le battement des pales de mORTEX)."""
    keys = ((0, 1), (0.14, 1.08), (0.28, 0.65), (0.42, 1.05), (0.56, 0.8), (0.7, 1), (1, 1))
    for (k0, v0), (k1, v1) in zip(keys, keys[1:]):
        if k <= k1:
            return _lerp(v0, v1, EASE_INOUT((k - k0) / (k1 - k0)))
    return 1.0


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
        self.footer = L(FOOTER)
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
        self.f_title.setPixelSize(50)
        self.f_title.setWeight(QFont.Weight.ExtraBold)
        self.f_title.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.5)
        self.f_sub = QFont(base)
        self.f_sub.setPixelSize(17)
        self.f_sub.setWeight(QFont.Weight.DemiBold)
        self.f_foot = QFont(base)
        self.f_foot.setPixelSize(10)
        self.f_foot.setWeight(QFont.Weight.Medium)
        self.f_foot.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.6)
        self.f_foot.setCapitalization(QFont.Capitalization.AllUppercase)

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
        t = 3000.0 if self.static else self.elapsed()  # image fixe : tout est en place, au repos
        p = QPainter(self)
        p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.TextAntialiasing
                         | QPainter.RenderHint.SmoothPixmapTransform)
        card = QRectF(MARGIN, MARGIN, WIDTH - 2 * MARGIN, HEIGHT - 2 * MARGIN)
        cx, cy = card.center().x(), card.center().y()

        opacity = 1.0
        if self._leave_at is not None and not self.static:
            k = _phase(self.elapsed(), self._leave_at, LEAVE_MS)
            s = _lerp(1, 0.05, EASE_LEAVE(k))
            p.translate(cx, cy)
            p.scale(s, s)
            p.translate(-cx, -cy)
            opacity = 1.0 if k < 0.7 else 1 - (k - 0.7) / 0.3

        # Arrivée de la carte : bascule en 3D qui se redresse
        k = EASE_CARD(_phase(t, 0, 900))
        opacity *= min(1.0, _phase(t, 0, 900) * 2.5)
        tr = QTransform()
        tr.translate(cx, cy)
        tr.rotate(_lerp(28, 0, k), Qt.Axis.XAxis)
        tr.rotate(_lerp(-14, 0, k), Qt.Axis.YAxis)
        s = _lerp(0.92, 1, k)
        tr.scale(s, s)
        tr.translate(-cx, -cy)
        p.setTransform(tr, True)
        p.setOpacity(max(0.0, opacity))

        self._paint_card(p, card, t)
        p.end()

    def _paint_card(self, p: QPainter, card: QRectF, t: float) -> None:
        shape = QPainterPath()
        shape.addRoundedRect(card, 16, 16)

        # Ombre portée douce (la fenêtre native n'en a pas : elle entourerait tout le cadre)
        p.setPen(Qt.PenStyle.NoPen)
        for i in range(10, 0, -1):
            p.setBrush(QColor(0, 0, 0, int(9 * (11 - i) / 10)))
            p.drawRoundedRect(card.adjusted(-i, -i + 8, i, i + 8), 16 + i, 16 + i)

        bg = QLinearGradient(card.topLeft(), QPointF(card.left() + card.width() * 0.6, card.bottom() + 120))
        bg.setColorAt(0, QColor("#34363d"))
        bg.setColorAt(0.55, QColor("#1b1c21"))
        bg.setColorAt(1, QColor("#121317"))
        p.setBrush(bg)
        p.drawPath(shape)

        p.save()
        p.setClipPath(shape)
        # Lueur orange derrière le logo
        glow = _phase(t, 300, 1400)
        if glow > 0:
            g = QRadialGradient(QPointF(card.left() + 80, card.center().y()), 120)
            g.setColorAt(0, QColor(255, 120, 30, int(56 * glow)))
            g.setColorAt(0.65, QColor(255, 120, 30, 0))
            p.setBrush(g)
            p.drawRect(card)
        self._paint_logo(p, QPointF(card.left() + 34 + 54, card.center().y()), t)
        self._paint_text(p, card, t)
        # Reflet qui balaie la carte
        k = EASE_INOUT(_phase(t, 1350, 1100))
        if 0 < k < 1:
            x = _lerp(card.left() - card.width() * 0.6, card.right() + card.width() * 0.3, k)
            band = card.width() * 0.4
            sh = QLinearGradient(QPointF(x, 0), QPointF(x + band, 0))
            sh.setColorAt(0, QColor(255, 255, 255, 0))
            sh.setColorAt(0.45, QColor(255, 255, 255, 26))
            sh.setColorAt(0.5, QColor(255, 255, 255, 46))
            sh.setColorAt(0.55, QColor(255, 255, 255, 26))
            sh.setColorAt(1, QColor(255, 255, 255, 0))
            p.save()
            p.translate(x + band / 2, card.center().y())
            p.rotate(8)
            p.translate(-(x + band / 2), -card.center().y())
            p.setBrush(sh)
            p.drawRect(QRectF(x, card.top() - card.height(), band, card.height() * 3))
            p.restore()
        p.restore()

        p.setBrush(Qt.BrushStyle.NoBrush)
        p.setPen(QPen(QColor(255, 255, 255, 20), 1))
        p.drawRoundedRect(card.adjusted(0.5, 0.5, -0.5, -0.5), 16, 16)

    def _paint_logo(self, p: QPainter, center: QPointF, t: float) -> None:
        """L'œil : le blanc se pose avec rebond, l'iris arrive en tourbillon, la pupille bat, un clin d'œil."""
        p.save()
        p.translate(center)
        p.scale(108 / 560, 108 / 560)
        p.translate(-EYE_CENTER.x(), -EYE_CENTER.y() + 26)

        # Clin d'œil à 2,4 s, puis toutes les 5 s
        blink = 1.0
        if t > 2400:
            k = ((t - 2400) % 5000) / 280
            if k < 1:
                blink = 1 - 0.92 * math.sin(math.pi * k)

        kw = _phase(t, 150, 1500)
        sw = _lerp(0.3, 1, EASE_WHITE(kw))
        p.translate(EYE_CENTER)
        p.scale(sw, sw * blink)
        p.translate(-EYE_CENTER)
        p.setOpacity(p.opacity() * _phase(t, 150, 450))
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor("#ffffff"))
        p.drawPath(EYE_WHITE)

        p.setClipPath(EYE_WHITE, Qt.ClipOperation.IntersectClip)
        ki = _phase(t, 0, 1300)
        e = EASE_IRIS(ki)
        angle = _lerp(-420, 0, e) + (360 * (t - 1300) / 9000 if t > 1300 else 0)
        si = _lerp(0.2, 1, e)
        p.setOpacity(p.opacity() * min(1.0, ki / 0.4))
        p.translate(IRIS_CENTER)
        p.scale(si, si)
        p.rotate(angle)
        iris = QConicalGradient(QPointF(0, 0), 90)
        for pos, col in ((0, "#ffb347"), (0.18, "#ff7a00"), (0.36, "#ff6a00"), (0.52, "#ffa938"),
                         (0.66, "#e08a3c"), (0.8, "#ff8c12"), (0.92, "#ffc070"), (1, "#ffb347")):
            iris.setColorAt(pos, QColor(col))
        p.setBrush(iris)
        p.drawEllipse(QPointF(0, 0), 162, 162)
        p.rotate(-angle)

        beat = _heartbeat(((t - 1300) % 1200) / 1200) if t > 1300 else 1.0
        sp = 1 + (beat - 1) * 0.6
        pupil = QLinearGradient(QPointF(0, -102), QPointF(0, 102))
        pupil.setColorAt(0, QColor("#4a2a0c"))
        pupil.setColorAt(1, QColor("#000000"))
        p.setBrush(pupil)
        p.drawEllipse(QPointF(0, 0), 102 * sp, 102 * sp)

        p.setBrush(QColor("#ffffff"))
        p.drawEllipse(QPointF(90, -48), 30, 30)
        p.drawEllipse(QPointF(61, -90), 13, 13)
        p.restore()

    def _paint_text(self, p: QPainter, card: QRectF, t: float) -> None:
        left = card.left() + 34 + 108 + 26
        avail = card.right() - 30 - left
        fm = QFontMetricsF(self.f_title)
        sub_h, rule_gap = 17 * 1.25, 10 + 2 + 9
        top = card.center().y() - (50 + rule_gap + sub_h) / 2
        base = top + fm.ascent() - (fm.ascent() + fm.descent() - 50) / 2

        # Titre : lettres qui basculent une à une
        p.save()
        p.setFont(self.f_title)
        x = left
        grad = QLinearGradient(QPointF(left, top), QPointF(left + 30, top + 50))
        grad.setColorAt(0, ORANGE_1)
        grad.setColorAt(1, ORANGE_2)
        for i, ch in enumerate(self.title):
            w = fm.horizontalAdvance(ch) + 0.5
            k = _phase(t, 450 + i * 70, 700)
            if k > 0:
                e = EASE_LETTER(k)
                oy = top + 50 * 0.85
                tr = QTransform()
                tr.translate(x + w / 2, oy + _lerp(14, 0, e))
                tr.rotate(_lerp(-95, 0, e), Qt.Axis.XAxis)
                tr.translate(-(x + w / 2), -oy)
                p.save()
                p.setTransform(tr, True)
                p.setOpacity(p.opacity() * min(1.0, k * 1.6))
                p.setPen(QPen(QBrush(grad), 1) if i == 0 else QColor("#ffffff"))
                p.drawText(QPointF(x, base), ch)
                p.restore()
            x += w
        p.restore()

        # Filet orange
        k = EASE_RULE(_phase(t, 950, 700))
        if k > 0:
            ry = top + 50 + 10
            rule = QLinearGradient(QPointF(left, 0), QPointF(left + avail, 0))
            rule.setColorAt(0, ORANGE_1)
            rule.setColorAt(0.6, ORANGE_2)
            rule.setColorAt(1, QColor(255, 94, 10, 0))
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(rule)
            p.drawRoundedRect(QRectF(left, ry, avail * k, 2), 1, 1)

        # Sous-titre : l'espacement se resserre, réduit au besoin pour tenir dans la carte
        k = _phase(t, 1100, 900)
        if k > 0:
            e = EASE_CARD(k)
            f = QFont(self.f_sub)
            spacing = _lerp(14, 5, e)
            f.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, spacing)
            width = QFontMetricsF(f).horizontalAdvance(self.subtitle) - spacing
            final = QFont(self.f_sub)
            final.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 5)
            fit = min(1.0, avail / max(1.0, QFontMetricsF(final).horizontalAdvance(self.subtitle) - 5))
            p.save()
            p.setFont(f)
            p.setPen(QColor("#d8d8d8"))
            p.setOpacity(p.opacity() * e)
            sy = top + 50 + rule_gap
            p.translate(left, sy)
            p.scale(fit, fit)
            p.setClipRect(QRectF(0, -4, (avail + 40) / fit, sub_h + 8))
            p.drawText(QRectF(0, 0, width + 40, sub_h), Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
                       self.subtitle)
            p.restore()

        # Mention en bas à droite
        k = _phase(t, 1500, 600)
        if k > 0:
            p.save()
            p.setFont(self.f_foot)
            p.setPen(QColor("#aaaaaa"))
            p.setOpacity(p.opacity() * k)
            p.drawText(QRectF(card.left(), card.bottom() - 10 - 14, card.width() - 18, 14),
                       Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignBottom, self.footer)
            p.restore()
