import unittest
from observe_pressure import summarize

class ObservationTests(unittest.TestCase):
    def sample(self,t,incoming,outgoing,used=100,stalled=0):
        return {"monotonic":t,"swap_in_pages":incoming,"swap_out_pages":outgoing,
                "swap_used_bytes":used,"ram_available_bytes":10000,
                "psi":{"memory.full":{"total":stalled}}}
    def test_rates_and_stalls_use_actual_elapsed_time(self):
        result=summarize([self.sample(1,100,200),self.sample(3,102,203,110,20000)],4096)
        self.assertEqual(result["swap_io_bytes"],5*4096)
        self.assertEqual(result["swap_out_peak_bytes_per_second"],3*4096/2)
        self.assertEqual(result["memory_full_stall_percent"],1)
        self.assertEqual(result["swap_growth_peak_bytes"],10)
    def test_counter_regression_is_not_zero_traffic(self):
        with self.assertRaises(ValueError):
            summarize([self.sample(1,100,100),self.sample(2,99,100)],4096)
