/* --------------------
   Case Study Questions
   --------------------*/

-- 1. What is the total amount each customer spent at the restaurant?
-- 2. How many days has each customer visited the restaurant?
-- 3. What was the first item from the menu purchased by each customer?
-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?
-- 5. Which item was the most popular for each customer?
-- 6. Which item was purchased first by the customer after they became a member?
-- 7. Which item was purchased just before the customer became a member?
-- 8. What is the total items and amount spent for each member before they became a member?
-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?
-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi - how many points do customer A and B have at the end of January?

select * from members 

select * from menu

select * from sales

-- 1. What is the total amount each customer spent at the restaurant?

select s.customer_id, sum(m.price) as total_spent from sales as s
join menu as m on s.product_id = m.product_id
group by s.customer_id

-- 2. How many days has each customer visited the restaurant?

select customer_id, count(distinct order_date) as visits from sales
group by customer_id

-- 3. What was the first item from the menu purchased by each customer?

select s.customer_id , m.product_name from sales as s
join menu as m on s.product_id = m.product_id
where s.order_date in (select min(order_date) from sales group by customer_id)

-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?

select top 1 m.product_name , count(s.order_date) as total from sales as s
join menu as m on s.product_id = m.product_id 
group by m.product_name
order by total desc

-- 5. Which item was the most popular for each customer?

with freq as(
select s.customer_id, m.product_name, count(m.product_name) as top_product,
dense_rank() over (partition by s.customer_id order by count(m.product_name) desc) as rnk
from sales as s 
join menu as m on s.product_id = m.product_id -- gabungkan table  
group by s.customer_id, m.product_name
)

select customer_id, product_name from freq 
where rnk = 1

-- 6. Which item was purchased first by the customer after they became a member?

with sale_joinned as(
select s.customer_id, s.order_date, m.product_name, mm.join_date, 
row_number() over (partition by s.customer_id order by s.order_date) as rnk
from sales as s
join menu m on s.product_id = m.product_id
join members mm on s.customer_id = mm.customer_id
where s.order_date >= mm.join_date
)

select customer_id, product_name from sale_joinned
where rnk = 1

-- 7. Which item was purchased just before the customer became a member?

with sale_before as(
select s.customer_id, s.order_date, m.product_name, mm.join_date, 
dense_rank() over (partition by s.customer_id order by s.order_date desc)  as rnk
from sales as s
join menu m on s.product_id = m.product_id
join members mm on s.customer_id = mm.customer_id
where s.order_date < mm.join_date
)

select customer_id, product_name from sale_before
where rnk = 1

-- 8. What is the total items and amount spent for each member before they became a member?

with totalbuy_before as(
select s.customer_id, m.product_name, count(m.product_name) as total_buy, m.price
from sales as s
join menu m on s.product_id = m.product_id
join members mm on s.customer_id = mm.customer_id
where s.order_date < mm.join_date
group by s.customer_id, m.product_name, m.price
)

select customer_id, sum(total_buy) as total_items, sum(total_buy * price) as total_price from totalbuy_before
group by customer_id

-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?

select s.customer_id, sum
						(case when m.product_name = 'sushi' then m.price*20
						else m.price*10 end) 
						as total_points 
from sales as s
join menu m on s.product_id = m.product_id
group by customer_id

-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi - how many points do customer A and B have at the end of January?

with points_summary as (
select s.customer_id, sum
						(case when m.product_name = 'sushi' and s.order_date< mm.join_date then m.price*20
						      when m.product_name <> 'sushi' and s.order_date< mm.join_date then m.price*10 
							  else 0 end) 
						as totalpoints_beforemember
					,sum
					(case when s.order_date >= mm.join_date and s.order_date <= dateadd(day,6,mm.join_date) then m.price*10*2
					 else 0 end) 
					 as totalpoints_duringweek
					,sum
					(case when m.product_name = 'sushi' and s.order_date > dateadd(day,6,mm.join_date) then m.price*20
						  when m.product_name <> 'sushi' and s.order_date > dateadd(day,6,mm.join_date) then m.price*10 
						  else 0 end) 
						as totalpoints_afterweek
from sales as s
join menu m on s.product_id = m.product_id
join members mm on s.customer_id = mm.customer_id
where s.order_date <= '2021-01-31'
group by s.customer_id)

select customer_id, sum(totalpoints_beforemember+totalpoints_duringweek+totalpoints_afterweek) as total from points_summary
group by customer_id

-- Join All The Things

select s.customer_id, s.order_date, m.product_name, m.price, case when s.order_date >= mm.join_date then 'Y'  
																  else 'N' end as member
from sales as s
join menu m on s.product_id = m.product_id
left join members mm on s.customer_id = mm.customer_id 

-- Rank All The Things

with combine as(
select s.customer_id, s.order_date, m.product_name, m.price, case when s.order_date >= mm.join_date then 'Y'  
																  else 'N' end as member
from sales as s
join menu m on s.product_id = m.product_id
left join members mm on s.customer_id = mm.customer_id
)

select *, case when member = 'N' then null
			   else dense_rank() OVER (partition by customer_id, member ORDER BY order_date) end as rnk
from combine