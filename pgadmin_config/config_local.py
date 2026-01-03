import os

# Base config dir
CONFIG_DIR = os.environ.get('PGADMIN_CONFIG_DIR', os.path.dirname(os.path.realpath(__file__)))

# Set the base data directory for pgAdmin to our config_dir/data
DATA_DIR = os.path.join(CONFIG_DIR, 'data')

# Set the SQLite database path within our DATA_DIR
SQLITE_PATH = os.path.join(DATA_DIR, 'pgadmin4.db')

# Other standard settings
SERVER_MODE = False