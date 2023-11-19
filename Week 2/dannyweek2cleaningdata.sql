---------------------------------------------------------------------------------------------------------------------
-- clear cache
---------------------------------------------------------------------------------------------------------------------

-- View Cache
select
    *
from
    sys.dm_exec_cached_plans
cross apply
    sys.dm_exec_sql_text(plan_handle)
order by
    usecounts desc;

-- Clear Entire Plan Cache
dbcc freeproccache;

---------------------------------------------------------------------------------------------------------------------
-- cleaning table customer orders
---------------------------------------------------------------------------------------------------------------------

-- create copy table
select * into customer_orders_clean from customer_orders

-- delete copy table
use dannyweek2 drop table customer_orders_clean

-- exclusions & extras
update customer_orders_clean
set exclusions = (case when exclusions = '' or exclusions like '%null%' then null else exclusions end),
    extras = (case when extras = '' or extras like '%null%' then null else extras end)

-- adding pizza name to table customer order
alter table customer_orders_clean
drop column pizza_name;

alter table customer_orders_clean
add pizza_name varchar(50);

update customer_orders_clean
set pizza_name = pizza_names.pizza_name
from customer_orders_clean 
join pizza_names on customer_orders_clean.pizza_id = pizza_names.pizza_id;

-- adding cancellation to table customer order
alter table customer_orders_clean
add cancellation varchar(23);

update customer_orders_clean
set cancellation = runner_orders_clean.cancellation
from customer_orders_clean 
left join runner_orders_clean on customer_orders_clean.order_id = runner_orders_clean.order_id;

-- print out the table copy and original
select * from customer_orders_clean
select * from customer_orders

-- read data type
exec sp_help customer_orders_clean
exec sp_help pizza_names
exec sp_help runner_orders_clean

---------------------------------------------------------------------------------------------------------------------
-- cleaning table runner orders
---------------------------------------------------------------------------------------------------------------------

-- create copy table
select * into runner_orders_clean from runner_orders

-- delete copy table
use dannyweek2 drop table runner_orders_clean

-- cleaning pickup time, distance, duration, cancellation
update runner_orders_clean
set pickup_time = (case when pickup_time like '%null%' then null else pickup_time end),
    distance = (case when distance like '%null%' then null 
				     when distance like '%km' then REPLACE(distance, 'km', '')
				else distance end),
	duration = (case when duration like '%minutes%' then replace(duration, 'minutes', '')
					 when duration like '%mins%' then replace(duration, 'mins', '')
					 when duration like '%minute%' then replace(duration, 'minute', '')
					 else duration end),
	cancellation = (case when cancellation = '' or cancellation like '%null%' then null else cancellation end)

-- read data type
exec sp_help runner_orders_clean

-- column distance from varchar to decimal
alter table runner_orders_clean
alter column distance decimal(3,1)

-- column duration from varchar to int
update runner_orders_clean
set duration = null
where duration = 'null' or isnumeric(duration) = 0;
alter table runner_orders_clean
alter column duration int;

-- checking if can use operater for distance and duration
select sum(distance) from runner_orders_clean
select sum(duration) from runner_orders_clean
where duration is not null;

-- print out the table copy and original
select * from runner_orders_clean
select * from runner_orders

---------------------------------------------------------------------------------------------------------------------
-- merge pizza names, recipes, topping name
---------------------------------------------------------------------------------------------------------------------

-- create copy table
select * into pizza_toppings_clean from pizza_toppings
select * into pizza_recipes_clean from pizza_recipes

-- create table pizza topping and and recipe
select
    pizza_id,
    cast(value as int) as topping_id
into
    new_pizza_toppings
from
    pizza_recipes
cross apply
    string_split(cast(toppings as varchar(max)), ',');

-- adding topping names to table new_pizza_toppings
alter table new_pizza_toppings
add topping_name varchar(max);

update new_pizza_toppings
set topping_name = pizza_toppings.topping_name
from new_pizza_toppings 
left join pizza_toppings on new_pizza_toppings.topping_id = pizza_toppings.topping_id;

-- column topping_name from text to varchar
alter table pizza_toppings_clean
add new_topping_name varchar(max);

update pizza_toppings_clean
set new_topping_name = cast(topping_name AS varchar(max));

alter table pizza_toppings_clean
drop column topping_name;

-- read the data type
exec sp_help new_pizza_topings
exec sp_help pizza_toppings

-- print the table
select * from pizza_toppings_clean
select * from pizza_recipes_clean
select * from new_pizza_toppings

---------------------------------------------------------------------------------------------------------------------
-- merge pizza customer orders, recipe
---------------------------------------------------------------------------------------------------------------------

-- Assuming your table is named 'orders'
select * into orders from customer_orders_clean

-- Assuming your table is named 'orders'
ALTER TABLE orders
ADD exclusion_1 INT,
    exclusion_2 INT,
    extra_1 INT,
    extra_2 INT;

UPDATE orders
SET exclusion_1 = CASE WHEN CHARINDEX(',', exclusions) > 0 THEN CAST(SUBSTRING(exclusions, 1, CHARINDEX(',', exclusions) - 1) AS INT)
                      ELSE CAST(exclusions AS INT)
                 END,
    exclusion_2 = CASE WHEN CHARINDEX(',', exclusions) > 0 THEN CAST(SUBSTRING(exclusions, CHARINDEX(',', exclusions) + 1, LEN(exclusions)) AS INT)
                      ELSE NULL
                 END,
    extra_1 = CASE WHEN CHARINDEX(',', extras) > 0 THEN CAST(SUBSTRING(extras, 1, CHARINDEX(',', extras) - 1) AS INT)
                   ELSE CAST(extras AS INT)
              END,
    extra_2 = CASE WHEN CHARINDEX(',', extras) > 0 THEN CAST(SUBSTRING(extras, CHARINDEX(',', extras) + 1, LEN(extras)) AS INT)
                   ELSE NULL
              END;

-- Assuming your orders table is named 'orders'
-- Assuming your pizza_toppings_clean table is named 'pizza_toppings_clean'

-- Add columns for exclusion and extra toppings
ALTER TABLE orders
ADD exclusion_1_topping NVARCHAR(MAX),
    exclusion_2_topping NVARCHAR(MAX),
    extra_1_topping NVARCHAR(MAX),
    extra_2_topping NVARCHAR(MAX);

-- Update the new columns based on matching topping names with topping_id
UPDATE orders
SET exclusion_1_topping = (SELECT new_topping_name FROM pizza_toppings_clean WHERE topping_id = orders.exclusion_1),
    exclusion_2_topping = (SELECT new_topping_name FROM pizza_toppings_clean WHERE topping_id = orders.exclusion_2),
    extra_1_topping = (SELECT new_topping_name FROM pizza_toppings_clean WHERE topping_id = orders.extra_1),
    extra_2_topping = (SELECT new_topping_name FROM pizza_toppings_clean WHERE topping_id = orders.extra_2);

-- Adding column ingredients
ALTER TABLE orders
ADD ingredients NVARCHAR(MAX);

UPDATE orders
SET ingredients = (
    SELECT STRING_AGG(topping_name, ',') WITHIN GROUP (ORDER BY topping_id)
    FROM new_pizza_toppings
    WHERE pizza_id = orders.pizza_id
);

-- concate exclusion 1,2 (remove) and extras 1,2 (add) into ingredients

-- read the data type
exec sp_help orders
exec sp_help pizza_toppings_clean

-- print the table
select * from orders
select * from pizza_toppings_clean

-- adding table exclusions and extras

ALTER TABLE customer_orders_clean
ADD record_id INT IDENTITY(1,1)

ALTER TABLE orders
ADD record_id INT IDENTITY(1,1)

DROP TABLE IF EXISTS extras
SELECT		
      c.record_id,
      TRIM(e.value) AS topping_id
INTO extras
FROM customer_orders_clean as c
	    CROSS APPLY string_split(c.extras, ',') as e;

DROP TABLE IF EXISTS exclusions
SELECT c.record_id,
	   TRIM(e.value) AS topping_id
INTO exclusions
FROM customer_orders_clean as c
	    CROSS APPLY string_split(c.exclusions, ',') as e;

select * from extras
select * from exclusions

---------------------------------------------------------------------------------------------------------------------
-- Create a new table named 'adjusted_pizza_recipes'
---------------------------------------------------------------------------------------------------------------------

CREATE TABLE adjusted_pizza_recipes (
    record_id INT PRIMARY KEY,
    pizza_name VARCHAR(255),
    adjust_full_recipe VARCHAR(MAX)
);

INSERT INTO adjusted_pizza_recipes (record_id, pizza_name, adjust_full_recipe)
SELECT 
    record_id,
    pizza_name,
    STRING_AGG(topping, ',') WITHIN GROUP (ORDER BY topping) AS adjust_full_recipe
FROM (
    SELECT 
        record_id,
        pizza_name,
        TRIM(value) AS topping
    FROM orders
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(CONCAT(ingredients, ',', ISNULL(extra_1_topping, ''), ',', ISNULL(extra_2_topping, '')), ISNULL(exclusion_1_topping, ''), ''), ISNULL(exclusion_2_topping, ''), ''), ',')
) AS AdjustedToppings
GROUP BY record_id, pizza_name;

select * from adjusted_pizza_recipes

---------------------------------------------------------------------------------------------------------------------
-- Create a new table named 'adjusted_pizza_recipes_split'
---------------------------------------------------------------------------------------------------------------------

CREATE TABLE adjusted_pizza_recipes_split (
    record_id INT,
    pizza_name VARCHAR(255),
    topping VARCHAR(MAX)
);

-- Insert data into the new table from the query result
INSERT INTO adjusted_pizza_recipes_split (record_id, pizza_name, topping)
SELECT 
    record_id,
    pizza_name,
    TRIM(value) AS topping
FROM adjusted_pizza_recipes
CROSS APPLY STRING_SPLIT(adjust_full_recipe, ',');

select * from adjusted_pizza_recipes_split

-- Remove rows with NULL or empty string in the topping column
DELETE FROM adjusted_pizza_recipes_split
WHERE topping IS NULL OR LTRIM(RTRIM(topping)) = '';

-- Select and display the updated data
select * from adjusted_pizza_recipes
select * from pizza_toppings_clean
SELECT * FROM adjusted_pizza_recipes_split;

---------------------------------------------------------------------------------------------------------------------
-- Create a new table named pizza_runner_ratings
---------------------------------------------------------------------------------------------------------------------

-- Create a table for runner ratings
CREATE TABLE pizza_runner_ratings (
    --rating_id INT PRIMARY KEY,
    order_id INT,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comments VARCHAR(255),
    --rating_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data with random ratings for orders 1 to 10
INSERT INTO pizza_runner_ratings (order_id, rating, comments)
VALUES
    (1, 4, 'Good service!'),
    (2, 5, 'Excellent delivery.'),
    (3, 3, 'On-time, but pizza was a bit cold.'),
    (4, 2, 'Late delivery and wrong order.'),
    (5, 4, 'Quick and friendly.'),
    (6, 5, 'Perfect delivery!'),
    (7, 1, 'Terrible service, never ordering again.'),
    (8, 3, 'Average delivery.'),
    (9, 5, 'Amazing service!'),
    (10, 4, 'Satisfied with the delivery.');

-- Adding columns customer_id | order_id | runner_id | rating | order_time | pickup_time | Time between order and pickup | Delivery duration | Average speed | Total number of pizzas
ALTER TABLE pizza_runner_ratings
ADD customer_id NVARCHAR(MAX),
    runner_id NVARCHAR(MAX),
    order_time DATETIME,
    pickup_time DATETIME,
    time_between_order_pickup DECIMAL(4, 2),
    delivery_duration DECIMAL(4, 2),
    average_speed_kmph DECIMAL(4, 1),
    total_pizzas INT;

update pizza_runner_ratings
set
    customer_id = subquery.customer_id,
    runner_id = subquery.runner_id,
    order_time = subquery.order_time,
    pickup_time = subquery.pickup_time,
    time_between_order_pickup = subquery.time_between_order_pickup,
    delivery_duration = subquery.delivery_duration,
    average_speed_kmph = subquery.average_speed_kmph,
    total_pizzas = subquery.total_pizzas
from (
    select
        prr.order_id,
        co.customer_id,
        ro.runner_id,
        co.order_time,
        ro.pickup_time,
        cast(datediff(minute, co.order_time, ro.pickup_time) as decimal(4, 2)) as time_between_order_pickup,
        ro.duration as delivery_duration,
        round(ro.distance / ro.duration * 60, 1) as average_speed_kmph,
        count(co.pizza_id) as total_pizzas
    from pizza_runner_ratings as prr
    left join customer_orders_clean as co on co.order_id = prr.order_id
    left join runner_orders_clean as ro on ro.order_id = prr.order_id
    group by prr.order_id, co.customer_id, ro.runner_id, co.order_time, ro.pickup_time, ro.duration, ro.distance
) as subquery
where pizza_runner_ratings.order_id = subquery.order_id;

select * from pizza_runner_ratings