# SQL_Project_Funnel_Channel_Analysis

SQL project to analyze the customer journey and marketing channels of an online store.

This project uses BigQuery SQL to find where shoppers drop off between product view, cart and purchase, and whether marketing channels convert differently. The data is synthetic (Google's theLook eCommerce dataset), so the project shows the method, not real shopper behavior.

> Dashboard screenshot below. Full queries are in the `sql/` folder.

## Database and Tools

- Google BigQuery (SQL)
- theLook eCommerce public dataset
- Looker Studio (dashboard)

## Key Findings (April 2026)

- 10,457 sessions, 5,207 purchases (49.8% conversion)
- Larger drop-off is between cart and purchase (33.6%), not before the cart (25.0%)
- No marketing channel stands out (conversion 49.0% to 51.3%, confirmed with confidence intervals and z-tests)
- 24.2% of gross revenue ($310K) is lost to cancellations and returns

## Files

- `sql/copy_thelook_ecommerce.sql`: copies the public tables into your own dataset
- `sql/dashboard.sql`: builds the tables behind the dashboard
- `sql/exploration.sql`: checks the assumptions behind the analysis

## Author

Thanapol Shongtuptim · [LinkedIn](https://www.linkedin.com/in/YOUR-PROFILE)
