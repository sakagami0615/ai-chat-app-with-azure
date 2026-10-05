import unittest
from pathlib import Path

from streamlit.testing.v1 import AppTest


APP_FILE = Path(__file__).resolve().parents[1] / "app" / "streamlit_app.py"


class HelloWorldTest(unittest.TestCase):
    def test_button_updates_visible_count(self):
        self.assertTrue(APP_FILE.is_file(), "Hello World app is missing")

        app = AppTest.from_file(str(APP_FILE)).run()
        self.assertFalse(app.exception)
        self.assertEqual(app.title[0].value, "Hello World")
        self.assertEqual(app.text[0].value, "Clicks: 0")

        app.button[0].click().run()
        self.assertFalse(app.exception)
        self.assertEqual(app.text[0].value, "Clicks: 1")


if __name__ == "__main__":
    unittest.main()
