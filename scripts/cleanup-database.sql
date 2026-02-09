-- Clean all data from workshop tables (order matters due to foreign keys)
TRUNCATE order_items, orders, customers RESTART IDENTITY;
