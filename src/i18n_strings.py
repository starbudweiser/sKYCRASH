"""Table de traductions complète : {texte français: (en, it, es)}."""
from i18n_engine_strings import TR as _ENGINE
from i18n_ui_strings import TR as _UI

TR = {**_ENGINE, **_UI}
