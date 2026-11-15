#!/usr/bin/env bash
# Download the 9 Olist CSVs into data/raw/.
# Preferred: Kaggle CLI (needs ~/.kaggle/kaggle.json). Fallback: public GitHub mirror
# of the same files (verified byte-identical against a second mirror, see README).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/raw
if command -v kaggle >/dev/null && [ -f ~/.kaggle/kaggle.json ]; then
  kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
else
  base="https://raw.githubusercontent.com/alaa-github/Olist_Dataset/HEAD/data"
  for f in olist_orders_dataset olist_order_reviews_dataset olist_order_items_dataset \
           olist_customers_dataset olist_sellers_dataset olist_products_dataset \
           olist_order_payments_dataset olist_geolocation_dataset product_category_name_translation; do
    curl -fsSL -o "data/raw/$f.csv" "$base/$f.csv"
  done
fi
md5sum data/raw/*.csv
