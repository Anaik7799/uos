"""Numerical oracle and rejection tests for the isolated real MAX graph."""
import math
import unittest
from ecology_max_worker import infer


class MaxGraphTest(unittest.TestCase):
    def test_actual_graph_matches_independent_softmax(self):
        req = {"operation": "linear_softmax", "features": [2.0, -1.0],
               "weights": [[1.0, 0.0], [0.0, 1.0]], "bias": [0.5, -0.5]}
        result = infer(req)
        expected = 1.0 / (1.0 + math.exp(-4.0))
        self.assertEqual(result["backend"], "modular_max_graph")
        self.assertAlmostEqual(result["probabilities"][0], expected, places=6)
        self.assertAlmostEqual(sum(result["probabilities"]), 1.0, places=6)
        self.assertEqual(result["class_index"], 0)
        req["features"] = [-2.0, 1.0]
        self.assertEqual(infer(req)["class_index"], 1)

    def test_rejects_malformed_inputs(self):
        good = {"operation": "linear_softmax", "features": [1.0],
                "weights": [[1.0, 0.0]], "bias": [0.0, 0.0]}
        for change in ({"features": []}, {"features": [float("nan")]},
                       {"features": [True]}, {"weights": [[1.0]]},
                       {"bias": [0.0]}, {"operation": "generate"},
                       {"features": [1.0] * 129}, {"extra": 1}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                infer(good | change)


if __name__ == "__main__":
    unittest.main()
