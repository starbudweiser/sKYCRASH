"""Consommation Jev comptée par l'appli (l'API ne donne pas le solde de crédits)."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import jev_client


class _Resp:
    def __init__(self, body):
        self.body = json.dumps(body).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return self.body


class JevUsageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.patch = mock.patch.object(jev_client, "USAGE_FILE", Path(self.tmp.name) / "jev_usage.json")
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def test_counts_requests_and_tokens(self):
        body = {"answers": {"q": {"type": "noul", "noul": 0.9}}, "usage": {"input_tokens": 280, "output_tokens": 20}}
        with mock.patch("urllib.request.urlopen", return_value=_Resp(body)):
            self.assertEqual(jev_client.system_one({"t": "x"}, {"q": {}}, key="k"), body["answers"])
            jev_client.system_one({"t": "x"}, {"q": {}}, key="k")
        u = jev_client.month_usage()
        self.assertEqual((u["requests"], u["input_tokens"], u["output_tokens"]), (2, 560, 40))

    def test_resets_on_new_month(self):
        jev_client.USAGE_FILE.write_text(json.dumps({"month": "2000-01", "requests": 9, "input_tokens": 5, "output_tokens": 5}))
        self.assertEqual(jev_client.month_usage()["requests"], 0)


if __name__ == "__main__":
    unittest.main()
