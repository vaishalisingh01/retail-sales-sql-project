"""
Generates a realistic (and slightly messy) retail sales dataset as CSV files.

The data is intentionally "dirty" so that the SQL cleaning step has real work to do:
  - duplicate customer and order rows
  - extra spaces and inconsistent letter case in names and cities
  - missing (NULL) values
  - a few negative / zero quantities

It also creates a second "batch" that arrives later, to practise incremental loading:
  - customer_updates.csv -> existing customers who moved city + brand-new customers
  - new_orders.csv       -> new orders from January 2026 + status changes to old orders

Run:  python scripts/generate_data.py
Output: data/customers.csv, data/products.csv, data/orders.csv,
        data/customer_updates.csv, data/new_orders.csv
"""

import csv
import os
import random
from datetime import date, timedelta

random.seed(42)  # same data every time you run it

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
os.makedirs(OUT_DIR, exist_ok=True)

FIRST_NAMES = ["Aarav", "Vivaan", "Aditya", "Ananya", "Diya", "Isha", "Rohan", "Kabir",
               "Priya", "Sneha", "Arjun", "Meera", "Karan", "Neha", "Rahul", "Pooja",
               "Siddharth", "Riya", "Varun", "Tanvi", "Amit", "Kavya", "Nikhil", "Sanya"]
LAST_NAMES = ["Sharma", "Verma", "Gupta", "Singh", "Patel", "Reddy", "Iyer", "Nair",
              "Mehta", "Joshi", "Kapoor", "Das", "Bose", "Khan", "Malhotra", "Rao"]
CITIES = {
    "Delhi": "North", "Gurugram": "North", "Chandigarh": "North", "Jaipur": "North",
    "Mumbai": "West", "Pune": "West", "Ahmedabad": "West",
    "Bengaluru": "South", "Chennai": "South", "Hyderabad": "South", "Kochi": "South",
    "Kolkata": "East", "Bhubaneswar": "East", "Patna": "East",
}

PRODUCTS = [
    # (name, category, unit_price)
    ("Wireless Mouse", "Electronics", 799), ("Bluetooth Headphones", "Electronics", 2499),
    ("USB-C Charger", "Electronics", 1199), ("Smart Watch", "Electronics", 4999),
    ("Laptop Stand", "Electronics", 1499), ("Mechanical Keyboard", "Electronics", 3499),
    ("Cotton T-Shirt", "Clothing", 499), ("Denim Jeans", "Clothing", 1599),
    ("Running Shoes", "Clothing", 2999), ("Hoodie", "Clothing", 1299),
    ("Formal Shirt", "Clothing", 999),
    ("Coffee Mug", "Home & Kitchen", 299), ("Non-stick Pan", "Home & Kitchen", 1099),
    ("Water Bottle", "Home & Kitchen", 399), ("Bedsheet Set", "Home & Kitchen", 1399),
    ("Table Lamp", "Home & Kitchen", 899),
    ("Notebook Pack", "Stationery", 249), ("Gel Pens (10)", "Stationery", 149),
    ("Backpack", "Stationery", 1199), ("Desk Organizer", "Stationery", 449),
]

PAYMENT_METHODS = ["UPI", "Credit Card", "Debit Card", "Cash on Delivery", "Net Banking"]
STATUSES = ["Delivered"] * 8 + ["Cancelled", "Returned"]


def messy(text):
    """Randomly add spaces / change case to simulate bad data entry."""
    r = random.random()
    if r < 0.08:
        return "  " + text + " "
    if r < 0.14:
        return text.upper()
    if r < 0.20:
        return text.lower()
    return text


# ---------- customers ----------
customers = []
for cid in range(1, 301):
    city = random.choice(list(CITIES))
    signup = date(2023, 1, 1) + timedelta(days=random.randint(0, 600))
    email = f"customer{cid}@example.com" if random.random() > 0.05 else ""  # some missing
    customers.append([
        cid,
        messy(f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"),
        email,
        messy(city),
        CITIES[city],
        signup.isoformat(),
    ])
# add duplicate customer rows
customers += random.sample(customers, 8)

with open(os.path.join(OUT_DIR, "customers.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["customer_id", "customer_name", "email", "city", "region", "signup_date"])
    w.writerows(customers)

# ---------- products ----------
with open(os.path.join(OUT_DIR, "products.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["product_id", "product_name", "category", "unit_price"])
    for pid, (name, cat, price) in enumerate(PRODUCTS, start=1):
        w.writerow([pid, name, cat, price])

# ---------- orders ----------
orders = []
start, end = date(2024, 1, 1), date(2025, 12, 31)
for oid in range(1, 3001):
    order_date = start + timedelta(days=random.randint(0, (end - start).days))
    pid = random.randint(1, len(PRODUCTS))
    qty = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 12, 8, 5])[0]
    if random.random() < 0.01:
        qty = random.choice([0, -1])  # bad data
    discount = random.choice([0, 0, 0, 5, 10, 15, 20])
    payment = random.choice(PAYMENT_METHODS) if random.random() > 0.03 else ""
    orders.append([
        oid,
        random.randint(1, 300),
        pid,
        order_date.isoformat(),
        qty,
        discount,
        payment,
        random.choice(STATUSES),
    ])
# add duplicate order rows
orders += random.sample(orders, 25)
random.shuffle(orders)

with open(os.path.join(OUT_DIR, "orders.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["order_id", "customer_id", "product_id", "order_date",
                "quantity", "discount_pct", "payment_method", "order_status"])
    w.writerows(orders)

# =====================================================================
# SECOND BATCH (arrives later) - used for SCD Type 2 and incremental load
# =====================================================================

# ---------- customer_updates.csv ----------
# The source system sends the FULL record for every customer that changed.
UPDATE_DATE = "2026-01-01"
original = {row[0]: row for row in customers}  # one row per customer_id
updates = []

# 15 existing customers moved to a different city
for cid in random.sample(range(1, 301), 15):
    _, name, email, old_city, _, signup = original[cid]
    new_city = random.choice([c for c in CITIES if c != old_city.strip().title()])
    updates.append([cid, name.strip(), email, new_city, CITIES[new_city], signup, UPDATE_DATE])

# 10 brand-new customers
for cid in range(301, 311):
    city = random.choice(list(CITIES))
    updates.append([
        cid,
        f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}",
        f"customer{cid}@example.com",
        city,
        CITIES[city],
        UPDATE_DATE,
        UPDATE_DATE,
    ])

with open(os.path.join(OUT_DIR, "customer_updates.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["customer_id", "customer_name", "email", "city", "region",
                "signup_date", "updated_at"])
    w.writerows(updates)

# ---------- new_orders.csv ----------
new_orders = []

# 200 new orders placed in January 2026 (customers 1-310, incl. the new ones)
for oid in range(3001, 3201):
    order_date = date(2026, 1, 1) + timedelta(days=random.randint(0, 30))
    pid = random.randint(1, len(PRODUCTS))
    qty = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 12, 8, 5])[0]
    new_orders.append([
        oid,
        random.randint(1, 310),
        pid,
        order_date.isoformat(),
        qty,
        random.choice([0, 0, 0, 5, 10, 15, 20]),
        random.choice(PAYMENT_METHODS),
        random.choice(STATUSES),
    ])

# 20 old delivered orders that the customer has now returned (status change)
delivered = {o[0]: o for o in orders if o[7] == "Delivered" and o[4] > 0}
for oid in random.sample(sorted(delivered), 20):
    changed = list(delivered[oid])
    changed[7] = "Returned"
    new_orders.append(changed)

# a few duplicate rows, because real feeds are never perfect
new_orders += random.sample(new_orders, 5)

with open(os.path.join(OUT_DIR, "new_orders.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["order_id", "customer_id", "product_id", "order_date",
                "quantity", "discount_pct", "payment_method", "order_status"])
    w.writerows(new_orders)

print("Done! Files written to the data/ folder:")
print(f"  customers.csv        -> {len(customers)} rows (includes duplicates)")
print(f"  products.csv         -> {len(PRODUCTS)} rows")
print(f"  orders.csv           -> {len(orders)} rows (includes duplicates)")
print(f"  customer_updates.csv -> {len(updates)} rows (15 moved, 10 new)")
print(f"  new_orders.csv       -> {len(new_orders)} rows (200 new, 20 status changes, 5 duplicates)")
