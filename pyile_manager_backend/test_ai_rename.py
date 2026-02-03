"""
Test script to verify AI renaming functionality with sample files.
"""

import sys
from pathlib import Path

# Add parent directory to path to import modules
sys.path.insert(0, str(Path(__file__).parent))

from pyile_manager_backend.ollama_api import rename_file_with_ai


def test_rename_files():
    """Test AI renaming with example files."""
    example_dir = Path("example_files")

    if not example_dir.exists():
        print("Error: example_files directory not found")
        return

    # Get all files in example directory
    files = list(example_dir.iterdir())

    print(f"Testing AI renaming on {len(files)} files...\n")

    for file_path in files:
        if file_path.is_file():
            print(f"Processing: {file_path.name}")
            print("-" * 60)

            try:
                new_name = rename_file_with_ai(str(file_path))

                if new_name:
                    print(f"  Original: {file_path.name}")
                    print(f"  AI Suggested: {new_name}{file_path.suffix}")
                    print("  ✓ SUCCESS")
                else:
                    print("  ✗ FAILED - No name generated")

            except Exception as e:
                print(f"  ✗ ERROR: {e}")

            print()


if __name__ == "__main__":
    print("=" * 60)
    print("Pyile Manager - AI Renaming Test")
    print("=" * 60)
    print()
    test_rename_files()
