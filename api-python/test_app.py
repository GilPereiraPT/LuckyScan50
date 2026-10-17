import unittest
from app import application, validate_result

class APITests(unittest.TestCase):
    def setUp(self):
        self.client = application.test_client()
    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["ok"])
    def test_empty_latest(self):
        response = self.client.get("/v1/draws/latest?game=invalid")
        self.assertEqual(response.status_code, 400)
    def test_invalid_result(self):
        with self.assertRaises(ValueError):
            validate_result({"game": "euromilhoes", "drawId": "bad"})

if __name__ == "__main__":
    unittest.main()
