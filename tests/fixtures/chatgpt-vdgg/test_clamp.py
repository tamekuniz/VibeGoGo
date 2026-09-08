import unittest
from clamp import clamp


class ClampTests(unittest.TestCase):
    def test_inside(self):
        self.assertEqual(clamp(3, 1, 5), 3)

    def test_bounds(self):
        self.assertEqual(clamp(-2, 0, 5), 0)
        self.assertEqual(clamp(8, 0, 5), 5)
        self.assertEqual(clamp(0, 0, 5), 0)
        self.assertEqual(clamp(5, 0, 5), 5)

    def test_equal_bounds(self):
        self.assertEqual(clamp(-1, 2, 2), 2)

    def test_inverted_bounds(self):
        with self.assertRaises(ValueError):
            clamp(3, 5, 1)

    def test_float(self):
        self.assertEqual(clamp(1.5, 0.0, 1.0), 1.0)
        self.assertIsInstance(clamp(1.5, 0.0, 1.0), float)


if __name__ == '__main__':
    unittest.main()
