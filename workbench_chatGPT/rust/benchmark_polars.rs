use anyhow::{Context, Result};
use serde::Serialize;
use std::time::Instant;
use polars::prelude::*;

#[derive(Serialize)]
struct BenchOut {
    engine: &'static str,
    read_s: f64,
    groupby_s: f64,
    rows: usize,
    cols: usize,
    notes: &'static str,
}

fn main() -> Result<()> {
    // Microbenchmark: read a local Parquet/CSV and run a simple groupby
    // Usage: place a file at ./data/input.parquet or ./data/input.csv
    let path_parquet = "data/input.parquet";
    let path_csv = "data/input.csv";

    let (df, read_s, note) = if std::path::Path::new(path_parquet).exists() {
        let t0 = Instant::now();
        let df = ParquetReader::from_path(path_parquet)?.finish()?;
        (df, t0.elapsed().as_secs_f64(), "parquet")
    } else if std::path::Path::new(path_csv).exists() {
        let t0 = Instant::now();
        let df = CsvReader::from_path(path_csv)?.finish()?;
        (df, t0.elapsed().as_secs_f64(), "csv")
    } else {
        // synthesize small DF
        let t0 = Instant::now();
        let df = df!(
            "id" => (0..1_000_000).collect::<Vec<i32>>(),
            "grp" => (0..1_000_000).map(|x| x % 10).collect::<Vec<i32>>(),
            "val" => (0..1_000_000).map(|x| (x as f64).sin()).collect::<Vec<f64>>()
        )?;
        (df, t0.elapsed().as_secs_f64(), "synthetic")
    };

    let t1 = Instant::now();
    let grouped = df.lazy()
        .groupby([col("grp")])
        .agg([col("val").mean().alias("mean_val")])
        .collect()?;
    let groupby_s = t1.elapsed().as_secs_f64();

    let out = BenchOut {
        engine: "rust-polars",
        read_s,
        groupby_s,
        rows: grouped.height(),
        cols: grouped.width(),
        notes: note,
    };
    println!("{}", serde_json::to_string_pretty(&out)?);
    Ok(())
}
