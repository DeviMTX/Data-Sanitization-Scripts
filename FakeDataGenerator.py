import csv
from faker import Faker
import time

# --- Configuration ---
NUM_RECORDS = 2000000
OUTPUT_FILE = 'fake_names.csv'

def generate_fake_names():
    """
    Generates a specified number of fake first and last names
    and saves them to a CSV file.
    """
    # Initialize the Faker generator
    fake = Faker()

    print(f"🚀 Starting data generation for {NUM_RECORDS:,} records...")
    start_time = time.time()

    try:
        # Open the file in write mode
        with open(OUTPUT_FILE, 'w', newline='', encoding='utf-8') as csvfile:
            # Create a CSV writer object
            writer = csv.writer(csvfile)
            
            # Write the header row
            writer.writerow(['FirstName', 'LastName'])

            # Loop to generate and write records
            for i in range(NUM_RECORDS):
                first_name = fake.first_name()
                last_name = fake.last_name()
                writer.writerow([first_name, last_name])

                # Print a progress update every 100,000 records
                if (i + 1) % 100000 == 0:
                    print(f"   ... {(i + 1):,} records generated.")
    
    except Exception as e:
        print(f"❌ An error occurred: {e}")
        return

    end_time = time.time()
    print(f"✅ Successfully generated {NUM_RECORDS:,} records in {end_time - start_time:.2f} seconds.")
    print(f"   File saved as: {OUTPUT_FILE}")


if __name__ == "__main__":
    generate_fake_names()
