"""
Simulates temperature sensor readings for storage units and shipments.
Normal readings stay inside the safe range; a few deliberate breaches
are planted so the alert trigger (Step 4) has something to detect.
Safe to re-run: it clears temperature_log first.
"""
import os
import random
from datetime import datetime, timedelta

import mysql.connector
from dotenv import load_dotenv

load_dotenv()
random.seed(42)

DAYS = 7
UNIT_INTERVAL_MIN = 10
SHIPMENT_INTERVAL_MIN = 10

# unit_id: (hours ago the breach starts, duration in hours, extreme temperature)
UNIT_BREACHES = {
    4: (30, 3.0, 12.0),    # Surat fridge: power failure, long and serious
    7: (55, 0.75, 9.5),    # Civil Hospital fridge: short spike
    2: (80, 2.0, -8.0),    # Central freezer: warms up
    9: (12, 1.0, 0.5),     # SSG fridge: too cold (freezing damage)
}

# shipment_id: (hours after dispatch the breach starts, duration in hours, extreme temperature)
SHIPMENT_BREACHES = {
    4: (1.0, 1.5, 12.5),   # refrigeration failure in transit
    2: (1.0, 0.5, 9.0),    # short, mild breach
}


def breach_shape(t, start, end):
    """0 outside the window; ramps up, holds, ramps down (0 to 1)."""
    if t < start or t > end:
        return 0.0
    pos = (t - start).total_seconds() / (end - start).total_seconds()
    return max(0.0, min(pos / 0.25, (1 - pos) / 0.25, 1.0))


conn = mysql.connector.connect(
    host=os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT")),
    database=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
)
cur = conn.cursor()
cur.execute("DELETE FROM temperature_log")

now = datetime.now().replace(second=0, microsecond=0)
rows = []

# Storage units
cur.execute("SELECT unit_id, sensor_id, min_temp, max_temp FROM storage_unit")
for unit_id, sensor_id, tmin, tmax in cur.fetchall():
    tmin, tmax = float(tmin), float(tmax)
    base = (tmin + tmax) / 2
    std = (tmax - tmin) / 10
    breach = UNIT_BREACHES.get(unit_id)
    t = now - timedelta(days=DAYS)
    while t <= now:
        temp = random.gauss(base, std)
        if breach:
            start = now - timedelta(hours=breach[0])
            end = start + timedelta(hours=breach[1])
            temp += breach_shape(t, start, end) * (breach[2] - base)
        rows.append((sensor_id, unit_id, None, t,
                     round(temp, 2), round(random.uniform(40, 60), 2)))
        t += timedelta(minutes=UNIT_INTERVAL_MIN)

# Shipments
cur.execute("""SELECT shipment_id, sensor_id, dispatch_time, actual_arrival
               FROM shipment WHERE dispatch_time IS NOT NULL""")
for ship_id, sensor_id, dispatch, arrival in cur.fetchall():
    end_time = arrival or now
    breach = SHIPMENT_BREACHES.get(ship_id)
    t = dispatch
    while t <= end_time:
        temp = random.gauss(5.0, 0.5)
        if breach:
            start = dispatch + timedelta(hours=breach[0])
            end = start + timedelta(hours=breach[1])
            temp += breach_shape(t, start, end) * (breach[2] - 5.0)
        rows.append((sensor_id, None, ship_id, t,
                     round(temp, 2), round(random.uniform(40, 60), 2)))
        t += timedelta(minutes=SHIPMENT_INTERVAL_MIN)

sql = """INSERT INTO temperature_log
         (sensor_id, unit_id, shipment_id, recorded_at, temperature, humidity)
         VALUES (%s, %s, %s, %s, %s, %s)"""
for i in range(0, len(rows), 1000):
    cur.executemany(sql, rows[i:i + 1000])
conn.commit()

cur.execute("SELECT COUNT(*) FROM temperature_log")
print("Total readings inserted:", cur.fetchone()[0])

cur.execute("""SELECT l.unit_id, COUNT(*)
               FROM temperature_log l JOIN storage_unit u ON u.unit_id = l.unit_id
               WHERE l.temperature NOT BETWEEN u.min_temp AND u.max_temp
               GROUP BY l.unit_id ORDER BY l.unit_id""")
print("Out-of-range readings per storage unit (unit_id, count):")
for row in cur.fetchall():
    print("  ", row)

cur.close()
conn.close()
