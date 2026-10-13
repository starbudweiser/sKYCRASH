import re
p = "src/compat.py"
s = open(p, encoding="utf-8").read()
s = s.replace("import struct\nfrom datetime import datetime\n", "import struct\nfrom datetime import datetime\n\nfrom i18n import L, N_\n", 1)
s2, n = re.subn(r'(\("[^"]+", )("[^"]+")(\),)', r'\1N_(\2)\3', s)
print("catalog entries wrapped:", n)
open(p, "w", encoding="utf-8").write(s2)
