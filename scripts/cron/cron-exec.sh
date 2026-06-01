# Test hot to warm rotation manually
./scripts/cron/rotate_hot_to_warm.sh

# Test warm to cold rotation manually  
./scripts/cron/rotate_warm_to_cold.sh

# View storage tier status
./scripts/cron/view_tiers.sh

# Setup automatic cron jobs
./scripts/cron/setup_cron.sh