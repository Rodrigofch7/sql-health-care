#!/usr/bin/env python3
"""
generate_charts.py
------------------
Connects to the `healthcare` PostgreSQL database, runs a set of analytical
queries, and saves chart images into this folder (data_visualization/).

All data is synthetic (see ../seed.sql).

Usage:
    # make sure Postgres is running and the healthcare DB is loaded, then:
    pip install matplotlib pandas psycopg2-binary
    python3 generate_charts.py

Connection: by default connects to dbname=healthcare over the local socket
as the current user. Override with standard libpq env vars if needed
(PGHOST, PGPORT, PGUSER, PGDATABASE).
"""

import os
import matplotlib

matplotlib.use("Agg")  # no display needed; write straight to files
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import pandas as pd
import psycopg2

# ----------------------------------------------------------------------
# Style — a clean, consistent "clinical" look shared by every chart
# ----------------------------------------------------------------------
INK = "#1f2d3d"        # near-black text
MUTED = "#7b8794"      # secondary text / gridlines
TEAL = "#0f8b8d"       # primary accent
TEAL_DK = "#0a5e60"
CORAL = "#e07a5f"      # secondary accent (for the "patient pays" / alerts)
SAND = "#d9c8a9"
PALETTE = ["#0f8b8d", "#3aa6a0", "#6cbfb0", "#e07a5f", "#d98e5a",
           "#c9a227", "#7b9e89", "#5a7d9a"]

plt.rcParams.update({
    "figure.figsize": (10, 6),
    "figure.dpi": 130,
    "savefig.dpi": 130,
    "savefig.bbox": "tight",
    "font.family": "DejaVu Sans",
    "font.size": 11,
    "text.color": INK,
    "axes.edgecolor": MUTED,
    "axes.labelcolor": INK,
    "axes.titlecolor": INK,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.spines.top": False,
    "axes.spines.right": False,
})

OUT = os.path.dirname(os.path.abspath(__file__))


def title_block(ax, title, subtitle):
    """Two-line title: bold question on top, lighter business context below."""
    ax.set_title(title, fontsize=15, fontweight="bold", loc="left", pad=24)
    ax.annotate(subtitle, xy=(0, 1), xytext=(0, 8),
                xycoords="axes fraction", textcoords="offset points",
                fontsize=10.5, color=MUTED, ha="left", va="bottom")


def footer(fig):
    fig.text(0.005, -0.02, "Synthetic data — Hospital Operations & Patient Analytics",
             fontsize=8, color=MUTED, ha="left")


def save(fig, name):
    path = os.path.join(OUT, name)
    fig.savefig(path)
    plt.close(fig)
    print(f"  saved {name}")


def q(conn, sql):
    return pd.read_sql_query(sql, conn)


# ----------------------------------------------------------------------
# Charts
# ----------------------------------------------------------------------

def chart_no_show(conn):
    df = q(conn, """
        SELECT d.name AS department,
               100.0 * AVG((a.status = 'no_show')::int) AS no_show_pct
        FROM appointments a
        JOIN doctors doc   ON doc.doctor_id = a.doctor_id
        JOIN departments d ON d.department_id = doc.department_id
        GROUP BY d.name
        ORDER BY no_show_pct;
    """)
    fig, ax = plt.subplots()
    bars = ax.barh(df["department"], df["no_show_pct"], color=TEAL)
    # highlight the worst offender in coral
    bars[-1].set_color(CORAL)
    for y, v in enumerate(df["no_show_pct"]):
        ax.text(v + 0.2, y, f"{v:.1f}%", va="center", fontsize=10, color=INK)
    ax.set_xlabel("No-show rate (%)")
    ax.xaxis.set_major_formatter(mticker.PercentFormatter(decimals=0))
    ax.margins(x=0.12)
    title_block(ax, "Which departments lose the most slots to no-shows?",
                "Share of appointments where the patient never showed up")
    footer(fig)
    save(fig, "no_show_by_department.png")


def chart_hours(conn):
    df = q(conn, """
        SELECT EXTRACT(HOUR FROM scheduled_at)::int AS hour, COUNT(*) AS appts
        FROM appointments
        GROUP BY hour ORDER BY hour;
    """)
    fig, ax = plt.subplots()
    ax.bar(df["hour"], df["appts"], color=TEAL, width=0.7)
    peak = df.loc[df["appts"].idxmax()]
    ax.bar(peak["hour"], peak["appts"], color=CORAL, width=0.7)
    ax.set_xlabel("Hour of day")
    ax.set_ylabel("Appointments")
    ax.set_xticks(df["hour"])
    ax.set_xticklabels([f"{h}:00" for h in df["hour"]], rotation=0, fontsize=9)
    ax.grid(axis="y", color=MUTED, alpha=0.2)
    title_block(ax, "When is the hospital busiest?",
                f"Appointment volume by hour — peak at {int(peak['hour'])}:00")
    footer(fig)
    save(fig, "appointments_by_hour.png")


def chart_readmission(conn):
    df = q(conn, """
        WITH visits AS (
            SELECT a.patient_id, a.scheduled_at, doc.department_id,
                   LEAD(a.scheduled_at) OVER (
                       PARTITION BY a.patient_id ORDER BY a.scheduled_at
                   ) AS next_visit
            FROM appointments a
            JOIN doctors doc ON doc.doctor_id = a.doctor_id
            WHERE a.status = 'completed'
        )
        SELECT d.name AS department,
               100.0 * AVG(
                   (next_visit IS NOT NULL
                    AND next_visit - scheduled_at <= INTERVAL '30 days')::int
               ) AS readmit_pct
        FROM visits v
        JOIN departments d ON d.department_id = v.department_id
        GROUP BY d.name
        ORDER BY readmit_pct DESC;
    """)
    fig, ax = plt.subplots()
    bars = ax.barh(df["department"][::-1], df["readmit_pct"][::-1], color=TEAL_DK)
    bars[-1].set_color(CORAL)
    for y, v in enumerate(df["readmit_pct"][::-1]):
        ax.text(v + 0.2, y, f"{v:.1f}%", va="center", fontsize=10, color=INK)
    ax.set_xlabel("30-day readmission rate (%)")
    ax.xaxis.set_major_formatter(mticker.PercentFormatter(decimals=0))
    ax.margins(x=0.12)
    title_block(ax, "30-day readmission rate by department",
                "Completed visits followed by another visit within 30 days (a key quality KPI)")
    footer(fig)
    save(fig, "readmission_rate_by_department.png")


def chart_revenue(conn):
    df = q(conn, """
        SELECT d.name AS department,
               SUM(b.insurance_covered)        AS insurance,
               SUM(b.patient_responsibility)   AS patient
        FROM billing b
        JOIN appointments a ON a.appointment_id = b.appointment_id
        JOIN doctors doc    ON doc.doctor_id = a.doctor_id
        JOIN departments d  ON d.department_id = doc.department_id
        GROUP BY d.name
        ORDER BY (SUM(b.insurance_covered) + SUM(b.patient_responsibility));
    """)
    fig, ax = plt.subplots()
    ax.barh(df["department"], df["insurance"] / 1000,
            color=TEAL, label="Insurance covered")
    ax.barh(df["department"], df["patient"] / 1000,
            left=df["insurance"] / 1000, color=CORAL, label="Patient responsibility")
    for y in range(len(df)):
        total = (df["insurance"].iloc[y] + df["patient"].iloc[y]) / 1000
        ax.text(total + 0.5, y, f"${total:,.0f}k", va="center", fontsize=9, color=INK)
    ax.set_xlabel("Revenue (thousands $)")
    ax.legend(loc="lower right", frameon=False)
    ax.margins(x=0.12)
    title_block(ax, "Revenue by department, and who pays it",
                "Total billed, split between insurer and patient")
    footer(fig)
    save(fig, "revenue_by_department.png")


def chart_top_meds(conn):
    df = q(conn, """
        SELECT m.name AS medication, COUNT(*) AS times_prescribed
        FROM prescriptions p
        JOIN medications m ON m.medication_id = p.medication_id
        GROUP BY m.name
        ORDER BY times_prescribed DESC
        LIMIT 10;
    """)
    df = df[::-1]
    fig, ax = plt.subplots()
    ax.barh(df["medication"], df["times_prescribed"], color=PALETTE[1])
    for y, v in enumerate(df["times_prescribed"]):
        ax.text(v + 1, y, str(v), va="center", fontsize=10, color=INK)
    ax.set_xlabel("Times prescribed")
    ax.margins(x=0.12)
    title_block(ax, "Top 10 prescribed medications",
                "Prescription volume across all completed visits")
    footer(fig)
    save(fig, "top_medications.png")


def chart_age(conn):
    df = q(conn, """
        SELECT DATE_PART('year', AGE(date_of_birth))::int AS age
        FROM patients;
    """)
    fig, ax = plt.subplots()
    ax.hist(df["age"], bins=range(0, 95, 5), color=TEAL, edgecolor="white")
    ax.set_xlabel("Patient age (years)")
    ax.set_ylabel("Number of patients")
    ax.grid(axis="y", color=MUTED, alpha=0.2)
    title_block(ax, "How old are our patients?",
                "Age distribution across the patient population")
    footer(fig)
    save(fig, "patient_age_distribution.png")


def chart_monthly(conn):
    df = q(conn, """
        SELECT DATE_TRUNC('month', scheduled_at) AS month, COUNT(*) AS appts
        FROM appointments
        GROUP BY month ORDER BY month;
    """)
    fig, ax = plt.subplots()
    ax.plot(df["month"], df["appts"], color=TEAL, linewidth=2.5,
            marker="o", markersize=5, markerfacecolor="white",
            markeredgecolor=TEAL, markeredgewidth=1.5)
    ax.fill_between(df["month"], df["appts"], color=TEAL, alpha=0.08)
    ax.set_ylabel("Appointments")
    ax.grid(axis="y", color=MUTED, alpha=0.2)
    ax.margins(y=0.15)
    title_block(ax, "Appointment volume over time",
                "Monthly completed + scheduled appointments")
    footer(fig)
    save(fig, "monthly_appointment_volume.png")


def main():
    conn = psycopg2.connect(dbname=os.environ.get("PGDATABASE", "healthcare"))
    print("Connected. Generating charts...")
    chart_no_show(conn)
    chart_hours(conn)
    chart_readmission(conn)
    chart_revenue(conn)
    chart_top_meds(conn)
    chart_age(conn)
    chart_monthly(conn)
    conn.close()
    print("Done. 7 charts written to data_visualization/.")


if __name__ == "__main__":
    main()
