
# Olist Customer Experience Analytics

**What is driving bad reviews at a Brazilian e-commerce marketplace, and what should the company do about it?**

End-to-end analytics project on ~96,000 real orders: MySQL data modelling, cleaning and feature engineering in Python, statistical testing, a predictive model, LLM-assisted analysis of Portuguese reviews, an Excel report for managers, and a one-page recommendation memo.

**Tools:** MySQL · Python (Pandas, NumPy, Matplotlib, Seaborn, SciPy, statsmodels, scikit-learn) · Gemini API · Excel (xlsxwriter)

---

## The business problem

Olist's review scores were sliding. Ops blamed delivery, seller relations blamed products, and marketing blamed more demanding customers. Nobody had numbers, and the company was about to renegotiate with its logistics partners.

## Key findings

| # | Finding | Evidence |
|---|---|---|
| 1 | **Late orders get bad reviews 6.7x as often** | 62.4% vs 9.2% bad (1-2 star) reviews. Gap of 53 points, 95% interval 52 to 54 |
| 2 | **It gets worse with every extra day of delay** | Bad-review rate: 9% on time, 32% at 1-3 days late, 68% at 4-7 days, 79% at 8+ days |
| 3 | **Lateness still matters after controlling for price, freight and distance** | Logistic regression: late orders had about 17x the odds of a bad review |
| 4 | **But delivery is not the whole story** | Late orders are ~7% of orders and explain about 28% of bad reviews. About two-thirds of bad reviews come from orders that arrived on time |
| 5 | **Late delivery is concentrated** | The 10% of sellers with the most late orders account for 74% of them. Late rates are worst in AL, MA and SE (small states), but **Rio de Janeiro** has the biggest excess: about 915 extra late orders vs São Paulo's rate (14% of all late orders) |
| 6 | **On-time complaints are about the contents, not the shipping** | Among on-time orders, complaints spread across quality (14%), missing items (12%), wrong product (11%), returns (10%) and misleading listings (7%) |

## Recommendations

1. **Target Rio de Janeiro first, then Bahia and the north-east, in the logistics renegotiation.** Matching São Paulo's late rate in Rio alone would remove ~915 late orders and avoid ~490 bad reviews (4% of the total).
2. **Set a maximum handoff-to-carrier time for sellers and review multi-item orders.** Slow handoff and larger orders were the strongest drivers in the model, and customers describe partial orders ("bought 3, received 2").
3. **Contact the riskiest orders before delivery.** The early-warning model reaches 24% of future bad reviews by flagging the riskiest 10% of orders.

Full reasoning, value estimates and uncertainties are in the [memo](memo/recommendation_memo.pdf).

---

## What I did

### 1. SQL (MySQL)
- Loaded 9 CSV tables and built a **one-row-per-order view** by aggregating items, payments and reviews *before* joining. This avoids the row duplication a naive join creates.
- Validated the result: 99,441 rows and 99,441 distinct orders.
- Wrote 8 analytical queries using CTEs and window functions (late rate by state, rolling monthly scores, seller concentration).
- 📁 `sql/`

### 2. Cleaning and features (Python)
- Kept delivered orders with a review, Jan 2017 to Aug 2018. Logged rows removed at each step.
- Kept extreme delivery times (genuine delays, not errors).
- Built delivery, distance (haversine), seller-handoff and freight features.
- Built **seller history features using only earlier orders**, so no future information leaks in.
- 📁 `notebooks/01_cleaning_features.ipynb`

### 3. EDA
- Score distribution, delay vs score, state and category views, seller concentration, monthly trend.
- 📁 `notebooks/02_eda.ipynb`

### 4. Statistics
- Compared bad-review rates with a chi-square test and a bootstrap confidence interval, checked the dose-response pattern, and used logistic regression to control for other factors.
- Estimated how much of the problem delivery explains (about 28%), rather than stopping at "it's significant".
- 📁 `notebooks/03_statistics.ipynb`

### 5. Early-warning model
- **Linear regression** on the review score, using only information known **before delivery** (price, freight, distance, promised time, seller history, handoff time). No delivery outcome or review data, to avoid leakage.
- **Time-based split:** trained on orders before May 2018 (70,318), tested on May to Aug 2018 (25,242).

| Model | MAE (stars) | R² |
|---|---|---|
| Baseline (predict average) | 0.955 | n/a |
| Purchase info only | 0.953 | -0.006 |
| + seller handoff time | **0.939** | **0.015** |

- **R² is low.** Before delivery, the biggest driver (lateness) is unknown. The model is a *ranking* tool, so I judged it on the business test:

| Flag the riskiest | Bad reviews caught | vs random |
|---|---|---|
| 5% | 15% | 3.0x |
| 10% | 24% | 2.4x |
| 20% | 39% | 1.9x |

The riskiest 20% of orders had a 19.3% bad-review rate vs 6.1% for the safest 20%.
- 📁 `notebooks/04_model.ipynb`

### 6. Review-text analysis (GenAI)
- 9,194 bad reviews had a comment (75%). Tagged them with keyword rules (Portuguese), then used **Gemini** on samples to find themes the rules missed and to translate examples.
- **Late orders:** about half mention not receiving the order and a quarter mention lateness. **On-time orders:** complaints spread across quality, missing items, wrong product and returns.
- The LLM also surfaced two themes the rules missed: partial orders and forced post-office pickup despite paid home delivery.
- Rules were about **72% accurate** in a hand check of 25 reviews, so theme shares are approximate. The late vs on-time comparison is the reliable part, since the same rules apply to both groups.
- 📁 `notebooks/05_review_themes.ipynb`

### 7. Excel report for managers
- 8 sheets, one question per sheet, no jargon, formula-driven tables, colour scales, charts and translated example reviews.
- 📁 `excel/Olist_CX_Report.xlsx`

### 8. Recommendation memo
- One page: the answer, three actions with value and evidence, and what I'm unsure about.
- 📁 `memo/`

---

## Screenshots

| | |
|---|---|
| ![Delay vs score](images/02_delay_vs_score.png) | ![States](images/03_states.png) |
| ![Seller concentration](images/05_seller_pareto.png) | ![Model coefficients](images/10_coefficients.png) |
| ![Themes by category](images/12_theme_by_category.png) | ![Excel report](images/excel_read_me.png) |

---

## Limitations

- **Observational data.** The link between lateness and bad reviews is strong and survives controls, but this analysis cannot prove cause. The "28%" figure assumes it is causal.
- **Reviews with text only** (75% of bad reviews), and commenters may differ from non-commenters.
- **Keyword rules over-match** on a few words, and about 31% of comments were unclassified (analysed separately with the LLM on a sample).
- **The model is modest.** It ranks risk but cannot predict exact scores, and it uses linear regression on star ratings, which treats stars as evenly spaced.
- **First-seller rule:** for the ~1% of orders with several sellers, the first seller is used.
- **Rio vs São Paulo:** São Paulo's shorter distances help its rate, so matching it may not be fully achievable.
- Standard errors in the regression don't account for orders from the same seller being related.

## How to reproduce

1. Download the [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) from Kaggle and put the 9 CSVs in `data/`.
2. Create the MySQL database and run `sql/01_create_tables.sql` and `sql/03_order_master_view.sql`, then load the CSVs (loading script in the cleaning notebook).
3. Install: `pip install pandas numpy matplotlib seaborn scipy statsmodels scikit-learn sqlalchemy pymysql xlsxwriter google-genai`
4. Run notebooks `01` to `06` in order. The GenAI notebook needs a free Gemini key in the `GEMINI_API_KEY` environment variable. **Never put the key in the code.**

```
├── data/          (not committed: raw Kaggle files)
├── sql/           table creation, quality checks, order view, analysis queries
├── notebooks/     01 cleaning, 02 EDA, 03 statistics, 04 model, 05 themes, 06 Excel
├── excel/         manager report
├── images/        charts used in this README
└── memo/          one-page recommendation memo
```

## Data

Public data released by Olist on Kaggle, anonymised. No attempt was made to identify anyone.
