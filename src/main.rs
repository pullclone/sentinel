use clap::Parser;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cli = sentinelctl::cli::Cli::parse();
    let code = match sentinelctl::app::run(cli).await {
        Ok(exit) => exit.code(),
        Err(e) => {
            eprintln!("{:#}", e);
            2
        }
    };
    std::process::exit(code);
}
