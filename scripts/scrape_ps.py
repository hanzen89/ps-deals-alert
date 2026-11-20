import json
import os
import re
import time
from datetime import datetime, timezone
import requests

LOCALE = "en-id"
CATEGORY_ID = "3f772501-f6f8-49b7-abac-874a88ca4897"
SHA256_HASH = "88c0b9a1273c6d320c51cd73e390924e21ae28bf09f01cde8b84b1034b16cd03"

MAX_PAGES = 10            # 10 halaman x 24 = 240 game diskon
PAGE_SIZE = 24
MIN_BASE_PRICE = 150000   # Filter game murah/shovelware di bawah Rp 100.000

HISTORY_FILE = "data/history.json"
OUTPUT_FILE = "docs/deals.json"
GRAPHQL_URL = "https://web.np.playstation.com/api/graphql/v1/op"


def parse_price(price_str: str | None) -> int:
    if not price_str:
        return 0
    digits = re.sub(r"[^\d]", "", price_str)
    return int(digits) if digits else 0


def parse_discount(discount_str: str | None) -> int:
    if not discount_str:
        return 0
    digits = re.sub(r"[^\d]", "", discount_str)
    return int(digits) if digits else 0


def fetch_page(offset: int) -> list[dict]:
    variables = {
        "id": CATEGORY_ID,
        "pageArgs": {"size": PAGE_SIZE, "offset": offset},
        "sortBy": None,
        "filterBy": [
                "storeDisplayClassification:FULL_GAME",
                "storeDisplayClassification:GAME_BUNDLE",
                "storeDisplayClassification:PREMIUM_EDITION",
        ],
        "facetOptions": [],
    }
    extensions = {
        "persistedQuery": {
            "version": 1,
            "sha256Hash": SHA256_HASH,
        }
    }
    params = {
        "operationName": "categoryGridRetrieve",
        "variables": json.dumps(variables, separators=(",", ":")),
        "extensions": json.dumps(extensions, separators=(",", ":")),
    }
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "x-psn-store-locale-override": LOCALE,
        "Accept": "application/json",
    }

    resp = requests.get(GRAPHQL_URL, params=params, headers=headers, timeout=20)
    resp.raise_for_status()
    data = resp.json()

    if "errors" in data:
        raise RuntimeError(f"GraphQL Error: {data['errors']}")

    return (
        data.get("data", {})
        .get("categoryGridRetrieve", {})
        .get("products", [])
    )


def load_history() -> dict:
    if os.path.exists(HISTORY_FILE):
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def main():
    history = load_history()
    now_iso = datetime.now(timezone.utc).isoformat()
    today_games = []

    for page in range(MAX_PAGES):
        offset = page * PAGE_SIZE
        print(f"Fetching offset {offset}...")
        products = fetch_page(offset)
        if not products:
            break

        for p in products:
            price_info = p.get("price") or {}
            base_price = parse_price(price_info.get("basePrice"))
            disc_price = parse_price(price_info.get("discountedPrice"))
            disc_pct = parse_discount(price_info.get("discountText"))

            if disc_pct <= 0 or disc_price <= 0 or base_price < MIN_BASE_PRICE:
                continue

            pid = p.get("id")
            if not pid:
                continue

            cover_url = ""
            for media in p.get("media", []):
                if media.get("role") in ("MASTER", "GAMEHUB_COVER_ART"):
                    cover_url = media.get("url", "")
                    break

            prev = history.get(pid)
            if prev is None:
                lowest_price = disc_price
                is_all_time_low = True
                history[pid] = {
                    "name": p.get("name"),
                    "lowest_price": lowest_price,
                    "first_seen": now_iso,
                    "last_seen": now_iso,
                }
            else:
                prev_low = prev["lowest_price"]
                is_all_time_low = disc_price <= prev_low
                lowest_price = min(prev_low, disc_price)
                prev["lowest_price"] = lowest_price
                prev["last_seen"] = now_iso

            today_games.append({
                "id": pid,
                "name": p.get("name"),
                "platforms": p.get("platforms", []),
                "base_price": base_price,
                "base_price_display": price_info.get("basePrice"),
                "discounted_price": disc_price,
                "discounted_price_display": price_info.get("discountedPrice"),
                "discount_percent": disc_pct,
                "lowest_price": lowest_price,
                "is_all_time_low": is_all_time_low,
                "cover_url": cover_url,
                "store_url": f"https://store.playstation.com/{LOCALE}/product/{pid}",
            })

        time.sleep(0.5)

    top_discounts = sorted(
        today_games,
        key=lambda x: (x["discount_percent"], x["base_price"]),
        reverse=True,
    )[:20]

    all_time_lows = sorted(
        [g for g in today_games if g["is_all_time_low"]],
        key=lambda x: (x["discount_percent"], x["base_price"]),
        reverse=True,
    )[:20]

    os.makedirs("data", exist_ok=True)
    os.makedirs("docs", exist_ok=True)

    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)

    output = {
        "updated_at": now_iso,
        "locale": LOCALE,
        "total_scanned": len(today_games),
        "top_discounts": top_discounts,
        "all_time_lows": all_time_lows,
    }
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"Done! Scanned {len(today_games)} deals.")


if __name__ == "__main__":
    main()
