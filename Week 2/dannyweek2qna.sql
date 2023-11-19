
select * from customer_orders_clean
select * from pizza_names
select * from pizza_recipes
select * from pizza_toppings
select * from runner_orders_clean
select * from runners

---------------------------------------------------------------------------------------------------------------------
--A. Pizza Metrics
---------------------------------------------------------------------------------------------------------------------

--How many pizzas were ordered?
select count(*) as total_ordered from customer_orders

--How many unique customer orders were made?
select count(distinct customer_id) as no_customers from customer_orders

--How many successful orders were delivered by each runner?
select runner_id, count(runner_id) as total_delivered from runner_orders
where duration is not null and duration <> 'null'
group by runner_id

--How many of each type of pizza was delivered?
select co.pizza_name, count(co.pizza_name) as total from customer_orders_clean as co
left join runner_orders_clean as ro on co.order_id = ro.order_id
where ro.cancellation is null
group by co.pizza_name

--How many Vegetarian and Meatlovers were ordered by each customer?
select customer_id, sum(case when pizza_name = 'Meatlovers' then 1 else 0 end) as Meatlovers, sum(case when pizza_name = 'Vegetarian' then 1 else 0 end) as Vegetarian
from customer_orders_clean
group by customer_id


--What was the maximum number of pizzas delivered in a single order?
select top 1 count(pizza_id) as total_pizza, order_id from customer_orders_clean
where cancellation is null
group by order_id
order by total_pizza desc

--For each customer, how many delivered pizzas had at least 1 change and how many had no changes?
select 
	customer_id, 
	sum(case when exclusions is null and extras is null then 1 else 0 end) as no_change,
	sum(case when exclusions is not null or extras is not null then 1 else 0 end) as change
from customer_orders_clean
where cancellation is null
group by customer_id

--How many pizzas were delivered that had both exclusions and extras?
select sum(case when exclusions is not null and extras is not null then 1 else 0 end) as change_pizza from customer_orders_clean
where cancellation is null

--What was the total volume of pizzas ordered for each hour of the day?
select datepart(hour, order_time) as hour_of_day, count(*) as pizza_ordered
from customer_orders_clean
group by datepart(hour, order_time)
order by hour_of_day

--What was the volume of orders for each day of the week?
select datename(weekday, order_time) as day_of_week, count(*) as volume_ordered
from customer_orders_clean
group by datename(weekday, order_time)
order by min(datepart(weekday, order_time))

---------------------------------------------------------------------------------------------------------------------
--B. Runner and Customer Experience
---------------------------------------------------------------------------------------------------------------------

-- How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)
set datefirst 1
select datepart(week, registration_date) as no_of_week, count (*) as total_registered 
from runners
group by datepart(week, registration_date)

-- What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
select ro.runner_id, round(avg(cast(abs(datediff(minute, co.order_time, ro.pickup_time)) as decimal(4,2))), 2) as average_pickup_time
from runner_orders_clean as ro
left join customer_orders_clean as co on co.order_id = ro.order_id
where ro.pickup_time is not null
group by ro.runner_id

-- Is there any relationship between the number of pizzas and how long the order takes to prepare?
with relationship_pizza_preparation as (
select co.order_id, count(co.pizza_id) as no_of_pizza, cast(datediff(minute, co.order_time, ro.pickup_time) as decimal (4,2)) as preparation_time
from customer_orders_clean as co
left join runner_orders_clean as ro on co.order_id = ro.order_id
group by co.order_id, co.order_time, ro.pickup_time
)

select no_of_pizza, sum(preparation_time)/count(no_of_pizza) as avg_preparation
from relationship_pizza_preparation
where preparation_time is not null
group by no_of_pizza

-- What was the average distance travelled for each customer?
select customer_id, round(avg(ro.distance),2) as avg_distance
from customer_orders_clean as co
left join runner_orders_clean as ro on co.order_id = ro.order_id
group by customer_id

-- What was the difference between the longest and shortest delivery times for all orders?
select max(duration) - min(duration) as diff from runner_orders_clean

-- What was the average speed for each runner for each delivery, and do you notice any trend for these values?
select runner_id, order_id, distance, duration, case when duration <> 0 then cast((distance / nullif(duration, 0)) * 60 as decimal (4,2)) else null end as speed_kmph 
from runner_orders_clean 
where duration is not null
order by distance 

-- What is the successful delivery percentage for each runner?
select runner_id, cast(sum(case when duration is not null then 1 else 0 end) as decimal)/count(order_id) * 100 as percentage_delivery
from runner_orders_clean
group by runner_id

---------------------------------------------------------------------------------------------------------------------
--C. Ingredient Optimisation
---------------------------------------------------------------------------------------------------------------------

-- What are the standard ingredients for each pizza?
select pizza_id, string_agg(topping_name, ',') as toppings
from new_pizza_toppings
group by pizza_id

-- What was the most commonly added extra?
select top 1 with ties pt.new_topping_name, count(*) as topping_count
from customer_orders_clean as co
cross apply string_split(co.extras, ',') as s
join pizza_toppings_clean as pt on try_cast(s.value as int) = pt.topping_id
where isnumeric(s.value) = 1 and pt.topping_id is not null
group by pt.new_topping_name
order by count(*) desc

-- What was the most common exclusion?
select top 1 with ties pt.new_topping_name, count(*) as topping_count
from customer_orders_clean as co
cross apply string_split(co.exclusions, ',') as s
join pizza_toppings_clean as pt on try_cast(s.value as int) = pt.topping_id
where isnumeric(s.value) = 1 and pt.topping_id is not null
group by pt.new_topping_name
order by count(*) desc

-- Generate an order item for each record in the customers_orders table in the format of one of the following:
/*Meat Lovers
Meat Lovers - Exclude Beef
Meat Lovers - Extra Bacon
Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers*/

select
    co.*,
    case
        when exclusions is null and extras is null then
            case
                when pizza_name = 'Meatlovers' then 'Meat Lovers'
                when pizza_name = 'Vegetarian' then 'Vegetarian Lovers'
                else 'No modifications'
            end
        else
            coalesce(
                case when pizza_name = 'Meatlovers' then 'Meat Lovers with ' else 'Vegetarian Lovers with ' end +
                case when exclusions is not null then 'exclude ' + exclusionslist else '' end +
                case when exclusions is not null and extras is not null then ' and ' else '' end +
                case when extras is not null then 'extras ' + extraslist else '' end,
                'Unknown modification'
            )
    end as order_details
from
    customer_orders_clean co
outer apply (
    select string_agg(ptc.new_topping_name, ', ') as exclusionslist
    from string_split(co.exclusions, ',') s_excl
    join pizza_toppings_clean ptc on try_cast(s_excl.value as int) = ptc.topping_id
) as exclusions
outer apply (
    select string_agg(ptc.new_topping_name, ', ') as extraslist
    from string_split(co.extras, ',') s_extras
    join pizza_toppings_clean ptc on try_cast(s_extras.value as int) = ptc.topping_id
) as extras;

-- Generate an alphabetically ordered comma separated ingredient list for each pizza order from the customer_orders table and add a 2x in front of any relevant ingredients
/*For example: "Meat Lovers: 2xBacon, Beef, ... , Salami"*/
select
    record_id,
    pizza_name,
    concat(pizza_name, ': ',
        case when count(case when topping = 'Bacon' then 1 end)/2 > 0 then concat(count(case when topping = 'Bacon' then 1 end)/2, 'xBacon, ') else '' end,
        case when count(case when topping = 'BBQ Sauce' then 1 end) > 0 then concat(count(case when topping = 'BBQ Sauce' then 1 end), 'xBBQ Sauce, ') else '' end,
        case when count(case when topping = 'Beef' then 1 end)/2 > 0 then concat(count(case when topping = 'Beef' then 1 end)/2, 'xBeef, ') else '' end,
        case when count(case when topping = 'Cheese' then 1 end)/2 > 0 then concat(count(case when topping = 'Cheese' then 1 end)/2, 'xCheese, ') else '' end,
        case when count(case when topping = 'Chicken' then 1 end)/2 > 0 then concat(count(case when topping = 'Chicken' then 1 end)/2, 'xChicken, ') else '' end,
        case when count(case when topping = 'Mushrooms' then 1 end)/2 > 0 then concat(count(case when topping = 'Mushrooms' then 1 end)/2, 'xMushrooms, ') else '' end,
        case when count(case when topping = 'Pepperoni' then 1 end)/2 > 0 then concat(count(case when topping = 'Pepperoni' then 1 end)/2, 'xPepperoni, ') else '' end,
        case when count(case when topping = 'Salami' then 1 end)/2 > 0 then concat(count(case when topping = 'Salami' then 1 end)/2, 'xSalami, ') else '' end,
        case when count(case when topping = 'Onions' then 1 end)/2 > 0 then concat(count(case when topping = 'Onions' then 1 end)/2, 'xOnions, ') else '' end,
        case when count(case when topping = 'Peppers' then 1 end)/2 > 0 then concat(count(case when topping = 'Peppers' then 1 end)/2, 'xPeppers, ') else '' end,
        case when count(case when topping = 'Tomato Sauce' then 1 end)/2 > 0 then concat(count(case when topping = 'Tomato Sauce' then 1 end)/2, 'xTomato Sauce, ') else '' end,
        case when count(case when topping = 'Tomatoes' then 1 end)/2 > 0 then concat(count(case when topping = 'Tomatoes' then 1 end)/2, 'xTomatoes') else '' end
    ) as list_order
from adjusted_pizza_recipes_split
group by record_id, pizza_name
order by record_id, pizza_name;

-- What is the total quantity of each ingredient used in all delivered pizzas sorted by most frequent first?
select topping,count(*)/2 as count_ingredients from adjusted_pizza_recipes_split
group by topping
order by count_ingredients desc

---------------------------------------------------------------------------------------------------------------------
-- D. Pricing and Ratings
---------------------------------------------------------------------------------------------------------------------

-- If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - how much money has Pizza Runner made so far if there are no delivery fees?
select sum(case when pizza_name = 'Meatlovers' then 12 else 10 end) as total_revenue
from orders
where cancellation is null

								
-- What if there was an additional $1 charge for any pizza extras? Add cheese is $1 extra
with table_price as (
select record_id,
	   sum(case when pizza_name = 'Meatlovers' then 12 else 10 end) as price_pizza,
	   sum(case when extra_1_topping = 'Cheese' or extra_2_topping = 'Cheese' then 2
				when extra_1 is not null then 1
				else 0 end) as extra_charges
from orders
where cancellation is null
group by record_id
)

select sum(price_pizza + extra_charges) as total_revenue from table_price

/*The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, 
how would you design an additional table for this new dataset - generate a schema for this new table 
and insert your own data for ratings for each successful customer order between 1 to 5.*/

-- Create a table for runner ratings
CREATE TABLE pizza_runner_ratings (
    order_id INT,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comments VARCHAR(255)
);

-- Insert sample data with random ratings for orders 1 to 10
INSERT INTO pizza_runner_ratings (order_id, rating, comments)
VALUES
    (1, 4, 'Good service!'),
    (2, 5, 'Excellent delivery.'),
    (3, 3, 'On-time, but pizza was a bit cold.'),
    (4, 2, 'Late delivery and wrong order.'),
    (5, 4, 'Quick and friendly.'),
    (7, 1, 'Terrible service, never ordering again.'),
    (8, 3, 'Average delivery.'),
    (10, 4, 'Satisfied with the delivery.');

select * from pizza_runner_ratings

/*Using your newly generated table - can you join all of the information together to form a table which has the following information for successful deliveries?
customer_id | order_id | runner_id | rating | order_time | pickup_time | Time between order and pickup | Delivery duration | Average speed | Total number of pizzas*/

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

/*If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras 
and each runner is paid $0.30 per kilometre traveled - 
how much money does Pizza Runner have left over after these deliveries?*/

with tbl_cost as (
select ro.order_id, sum(case when co.pizza_id = 1 then 1 else 0 end)*12 as price_meatlover, sum(case when co.pizza_id = 2 then 1 else 0 end)*10 as price_veg, ro.distance, ro.distance * 0.3 as pay_runner
from runner_orders_clean as ro
join customer_orders_clean as co on co.order_id = ro.order_id
where ro.cancellation is null
group by ro.order_id, ro.distance
)

select sum(price_meatlover + price_veg) - sum(pay_runner) as left_earn from tbl_cost