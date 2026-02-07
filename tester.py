"""
Random file to use for testing if there are no python scripts to test
"""

import argparse

parser = argparse.ArgumentParser(description="Testing tmux script")
parser.add_argument("-c", "--clone_name", required=True, help="The name of the clone to greet.")
parser.add_argument("-n", "--clone_count", type=int, required=True, help="Number of clones to greet")
parser.add_argument("--greet", action="store_true", required=True, help="Include a greeting (default: False).")

args = parser.parse_args()

# emoji for encoding check
for i in range(args.clone_count):
    print(f"👽 says: Hello, {args.clone_name}{i}!")