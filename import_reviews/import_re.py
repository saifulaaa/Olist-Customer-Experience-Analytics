
import pandas as pd
from sqlalchemy import create_engine, text

# 1. Database connection
engine = create_engine(
    "mysql+pymysql://root:Saif!Zara!2028@localhost:3306/olist_ecommerce?charset=utf8mb4"
)

# 2. CSV file path
file_path = r"C:\Users\Gafoo\OneDrive\Documents\GitHub\Olist-Customer-Experience-Analytics\data\reviews.csv"

# 3. Import data in chunks
total_rows = 0

for chunk in pd.read_csv(file_path, chunksize=5000):

    chunk.to_sql(
        name="reviews",
        con=engine,
        if_exists="append",
        index=False,
        method="multi",
        chunksize=1000
    )

    total_rows += len(chunk)

    print(f"Imported {total_rows} rows successfully")

# 4. Verify database row count
with engine.connect() as connection:
    count = connection.execute(
        text("SELECT COUNT(*) FROM reviews")
    ).scalar()

print("Total records in MySQL:", count)

engine.dispose()
