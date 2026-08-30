"""여러 개의 엑셀/CSV 파일을 하나로 취합합니다.

실무에서 흔한 형태를 전제로 만들었습니다. 지점별·월별로 쪼개져 있고,
컬럼 이름이 파일마다 조금씩 다르고, 머리글이 1행이 아닌 경우입니다.

    python merge.py ./입력폴더 -o 결과.xlsx

무엇이 어떻게 합쳐졌는지 merge_log.txt 에 남습니다. 원본은 건드리지 않습니다.
"""

import argparse
import logging
import re
import sys
from pathlib import Path

import pandas as pd

SUPPORTED = {".xlsx", ".xls", ".csv"}

# 파일마다 다르게 적힌 컬럼명을 하나로 모읍니다. 현장에서 나오는 대로 추가하세요.
COLUMN_ALIASES = {
    "거래처": ["거래처", "거래처명", "업체", "업체명", "고객사", "customer"],
    "날짜": ["날짜", "일자", "거래일", "거래일자", "date"],
    "품목": ["품목", "품명", "상품명", "제품명", "item"],
    "수량": ["수량", "개수", "qty", "quantity"],
    "단가": ["단가", "가격", "단위가격", "price"],
    "금액": ["금액", "합계", "총액", "공급가액", "amount", "total"],
}

log = logging.getLogger("merge")


def setup_logging(log_path: Path) -> None:
    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s", "%H:%M:%S")
    log.setLevel(logging.INFO)
    for handler in (logging.FileHandler(log_path, encoding="utf-8"),
                    logging.StreamHandler(sys.stdout)):
        handler.setFormatter(fmt)
        log.addHandler(handler)


def normalize(name: object) -> str:
    """공백·괄호·단위 표기를 걷어내고 비교 가능한 형태로 만듭니다."""
    text = re.sub(r"\(.*?\)|\s+", "", str(name)).lower()
    return re.sub(r"[^0-9a-z가-힣]", "", text)


def canonical_columns(columns) -> dict:
    lookup = {normalize(a): std for std, aliases in COLUMN_ALIASES.items() for a in aliases}
    return {col: lookup[normalize(col)] for col in columns if normalize(col) in lookup}


def find_header_row(raw: pd.DataFrame, scan: int = 10) -> int:
    """머리글이 몇 번째 행인지 찾습니다. 제목·로고 때문에 밀려 있는 경우가 많습니다."""
    best_row, best_hits = 0, 0
    for i in range(min(scan, len(raw))):
        hits = len(canonical_columns(raw.iloc[i].tolist()))
        if hits > best_hits:
            best_row, best_hits = i, hits
    return best_row


def read_one(path: Path) -> pd.DataFrame | None:
    try:
        if path.suffix.lower() == ".csv":
            for encoding in ("utf-8-sig", "cp949", "euc-kr"):
                try:
                    raw = pd.read_csv(path, header=None, dtype=str, encoding=encoding)
                    break
                except UnicodeDecodeError:
                    continue
            else:
                log.error("%s — 인코딩을 판별하지 못했습니다", path.name)
                return None
        else:
            raw = pd.read_excel(path, header=None, dtype=str)
    except Exception as exc:
        log.error("%s — 읽기 실패: %s", path.name, exc)
        return None

    if raw.empty:
        log.warning("%s — 빈 파일이라 건너뜁니다", path.name)
        return None

    header_row = find_header_row(raw)
    df = raw.iloc[header_row + 1:].copy()
    df.columns = raw.iloc[header_row]
    df = df.dropna(how="all").dropna(axis=1, how="all")

    mapping = canonical_columns(df.columns)
    if not mapping:
        log.warning("%s — 알아볼 수 있는 컬럼이 없습니다. 건너뜁니다", path.name)
        return None

    df = df.rename(columns=mapping)
    df["원본파일"] = path.name
    log.info("%s — %d행, 컬럼 %s", path.name, len(df), ", ".join(sorted(set(mapping.values()))))
    return df


def clean(df: pd.DataFrame) -> pd.DataFrame:
    if "날짜" in df:
        df["날짜"] = pd.to_datetime(df["날짜"], errors="coerce").dt.date
    for col in ("수량", "단가", "금액"):
        if col in df:
            df[col] = pd.to_numeric(
                df[col].astype(str).str.replace(r"[,\s원]", "", regex=True), errors="coerce"
            )
    # 단가·수량은 있는데 금액이 비어 있으면 채워둡니다.
    if {"수량", "단가", "금액"} <= set(df.columns):
        filled = df["금액"].isna() & df["수량"].notna() & df["단가"].notna()
        if filled.any():
            df.loc[filled, "금액"] = df.loc[filled, "수량"] * df.loc[filled, "단가"]
            log.info("금액이 비어 있던 %d행을 수량×단가로 채웠습니다", int(filled.sum()))
    return df


def main() -> int:
    parser = argparse.ArgumentParser(description="엑셀/CSV 파일을 하나로 취합합니다.")
    parser.add_argument("folder", type=Path, help="입력 파일이 있는 폴더")
    parser.add_argument("-o", "--output", type=Path, default=Path("취합결과.xlsx"))
    parser.add_argument("--keep-duplicates", action="store_true", help="중복 행을 남깁니다")
    args = parser.parse_args()

    setup_logging(args.output.parent / "merge_log.txt")

    if not args.folder.is_dir():
        log.error("폴더를 찾을 수 없습니다: %s", args.folder)
        return 1

    files = sorted(p for p in args.folder.rglob("*")
                   if p.suffix.lower() in SUPPORTED and not p.name.startswith("~$"))
    if not files:
        log.error("%s 안에 엑셀/CSV 파일이 없습니다", args.folder)
        return 1

    log.info("파일 %d개를 확인했습니다", len(files))
    frames = [df for df in (read_one(p) for p in files) if df is not None]
    if not frames:
        log.error("취합할 수 있는 파일이 하나도 없습니다")
        return 1

    merged = clean(pd.concat(frames, ignore_index=True))

    if not args.keep_duplicates:
        keys = [c for c in ("날짜", "거래처", "품목", "수량", "금액") if c in merged]
        before = len(merged)
        merged = merged.drop_duplicates(subset=keys or None)
        if before != len(merged):
            log.info("중복 %d행을 제거했습니다", before - len(merged))

    ordered = [c for c in COLUMN_ALIASES if c in merged] + ["원본파일"]
    merged = merged[ordered + [c for c in merged.columns if c not in ordered]]

    merged.to_excel(args.output, index=False)
    log.info("완료 — %s (%d행)", args.output, len(merged))

    if "금액" in merged and merged["금액"].notna().any():
        log.info("금액 합계: %s원", f"{merged['금액'].sum():,.0f}")
    if merged.isna().any().any():
        blanks = merged.isna().sum()
        log.warning("빈 칸이 있습니다 — %s",
                    ", ".join(f"{c} {n}건" for c, n in blanks[blanks > 0].items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
