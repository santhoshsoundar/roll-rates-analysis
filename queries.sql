--Objective: Visualize roll rates (dashboard) for loans by funding cohort to enable decision makers understand 
--roll rates in the loan portfolio and address the problem of 'Bad Debts'.

-----------Exploratory Data Analysis-----------------

-- Table snapshot:
SELECT * FROM loandata;
SELECT * FROM public.servicingdata
ORDER BY loanid ASC, period ASC LIMIT 100


select count(*) 			 as total_Records
	, count(distinct loanid) as unique_loans
from loandata;
--2901 records and loans. (No discrepancies)

select period
	, count(*) 				 as total_Records
	, count(distinct loanid) as unique_loans
from servicingdata
group by period;
-- Period with increasing records every month

--Funded loans by month
select 
	EXTRACT(year from funddt) * 100 + EXTRACT(month from funddt) as yrmonth
	, count(*) as unique_loans
from loandata
group by 1
order by 1;
-- [loandata] evenly distributed monthly loan grants


select count(distinct loanid) as unique_laons
from servicingdata;
--Why are there only 2041 unique loans in servicing data which is less compared to total funded loans. 
--May be the funded loans have not started repaying yet, so no data available. 


--Percentage of delinquent loans 
select cohort 
	, count(*) 									as records 
	, count(distinct loanid) 					as unique_loans 
	, sum(delinquent_flag) 						as delinquent_loans 
	, (sum(delinquent_flag) / count(*) ) / 100  as delinquent_loan_pct 
from 
(
	select EXTRACT(year from a.funddt) * 100 + EXTRACT(month from a.funddt) as cohort
		, a.loanid 
		, b.delinquent_flag
	from loandata as a 
	left join 
		(select loanid
			, max(case when currentdaysdelinquent > 0 then 1 else 0 end)	as delinquent_flag
		from servicingdata 
		group by 1
 		) as b 
	on a.loanid = b.loanid
) as C
group by 1
;


--Validation check - statistical summary of currentdaysdelinquent & dayspastdue
select period
	, min(currentdaysdelinquent) as min_delinquent 
	, max(currentdaysdelinquent) as max_delinquent
	, sum(currentdaysdelinquent) as sum_delinquent
	, min(dayspastdue) 			 as min_dayspastdue
	, max(dayspastdue) 			 as max_dayspastdue
	, sum(dayspastdue) 			 as sum_dayspastdue 
from servicingdata
group by 1
order by 1;

--------Understading the distribution------:

--Distinct interest rates
select rate 
from loandata
	, count(*) as loans 
group by rate
order by rate
--8 Unique interest rates

--Distinct System size
select cast(systemsize as int) as systemsize
	, count(distinct loanid)   as unique_loans
from loandata
group by 1
order by 1

--Creating bins for system size as there are so many unique values
1-4, 5-8, 9-12, 12+

--Program fee 
select programfee 
	, count(*) as loans
from loandata
group by 1
order by 1

--Creating bins for program fee as there are so many unique values
1-5, 6-10, 11-15, 16-20, 20-25, 25+

-- State data count
select state 
	, count(*) as records
from loandata 
group by 1
order by 1

-----Analysis to create a table with roll rate percentage for different delinquency categories ------

--Step 1: --Define cohort, 
drop table table_wt_cohort;
create temp table table_wt_cohort as
	select a.loanid
		, b.loanid 															as b_loanid
		, a.period
		, case when a.autopay = 'YES' then 1 else 0 end 					as autopay_flag
		, a.currentdaysdelinquent
		, case when a.currentdaysdelinquent between 1   and 30 	then '001-030'
			   when a.currentdaysdelinquent between 31  and 60  then '031-060'
			   when a.currentdaysdelinquent between 61  and 90  then '061-090'
			   when a.currentdaysdelinquent between 91  and 120 then '091-120'
			   when a.currentdaysdelinquent between 121 and 150 then '121-150'
			   when a.currentdaysdelinquent between 151 and 180 then '151-180'
			   when a.currentdaysdelinquent > 180 then '181+'
			   else '0' end 												as delinquency_bin
		, a.dayspastdue
		-- Fund month will be used to define the loans cohort
		, EXTRACT(year from b.funddt) * 100 + EXTRACT(month from b.funddt)  as fund_month
		, b.term 
		, b.state 
		, b.rate 
		, b.systemsize
		--Below variables are binned after seeing the distribution of the loan customers by the respective variable
		, case when cast(systemsize as int) between 1 and 4 then COALESCE(NULL::numeric::text, '01-04')
				when cast(systemsize as int) between 5 and 8 then COALESCE(NULL::numeric::text, '05-08')
				when cast(systemsize as int) between 9 and 12 then COALESCE(NULL::numeric::text, '09-12')
				when cast(systemsize as int) > 12 then COALESCE(NULL::numeric::text, '13+')
				else null 
			end 															as systemsize_bin
		, b.programfee
		, case when cast(programfee as int) between 1 and 5 then COALESCE(NULL::numeric::text, '01-05')
			when cast(programfee as int) between 6 and 10 then COALESCE(NULL::numeric::text, '06-10')
			when cast(programfee as int) between 11 and 15 then COALESCE(NULL::numeric::text, '11-15')
			when cast(programfee as int) between 16 and 20 then COALESCE(NULL::numeric::text, '16-20')
			when cast(programfee as int) between 21 and 25 then COALESCE(NULL::numeric::text, '21-25')
			when cast(programfee as int) > 25 then COALESCE(NULL::numeric::text, '26+')
			else null 
			end 															as programfee_bin
	from servicingdata 		 as a
	full outer join loandata as b 
		on a.loanid = b.loanid
;
select * from table_wt_cohort;


--How many loans are in servicing (started repayment) amongst all the funded loans? 
create temp table cohort_loans_distribution as 
	select fund_month 
		, count(distinct loanid) 	as unique_service_loans
		, count(distinct b_loanid) 	as total_funded_loans
	from table_wt_cohort
	group by 1;

select * from cohort_loans_distribution;
--All funded loans until 2020'02 are servicing loans. 
--In Mar and May, 2020, there are no funded loans that are in servicing. While in Apr, 2020 there is just 1 loan in servicing.


--# of servicing loans in different delinquency categories for each cohort
	select fund_month 				as cohort
		, delinquency_bins
		, count(distinct loanid) 	as servicing_loans
	from table_wt_cohort
	group by 1,2;
-- ignore bin ordering within grouped values


--Step 2: Calculate loans by delinquency categories for each cohort and add total unique funded loans by cohort:
drop table table_loans_by_cohort;
create temp table table_loans_by_cohort as 
	select 
		a.state
		, a.term 
		, a.rate
		, a.systemsize_bin
		, a.programfee_bin
		, a.fund_month 
		, b.total_funded_loans
		, a.delinquency_bin
		, a.loans_by_delinquency
	 	, b.total_serv_loans
	from (
			--Loans by cohort, dimensions and delinquency categories
			select 
				state 
				, term 
				, rate
				, systemsize_bin
				, programfee_bin
				, fund_month 
				, delinquency_bin
				, count(distinct loanid) 	as loans_by_delinquency
			from table_wt_cohort
			group by 1,2,3,4,5,6,7
			order by 1,2,3,4,5,6,7
		) as a 
	left join 
		(
			--Total funded and servicing loans by cohort and dimensions [Not by delinquency categories]: 
			--(This is just to get a view of the total loans in comparison to loans by delinquency)
			select 
				state 
				, fund_month 
				, term 
				, rate 
				, systemsize_bin
				, programfee_bin
				, count(distinct loanid) 	as total_serv_loans
				, count(distinct b_loanid) 	as total_funded_loans
			from table_wt_cohort
			group by 1,2,3,4,5,6
		) as b 
		on a.fund_month = b.fund_month 
			and a.state = b.state
			and a.term = b.term 
			and a.rate = b.rate 
			and a.systemsize_bin = b.systemsize_bin
			and a.programfee_bin = b.programfee_bin
;

select * from table_loans_by_cohort;


--Step 3: Calculate # of loans of previous delinquency categories for calculating roll over rate: 
drop table table_del_wt_lag;
create temp table table_del_wt_lag as 
	select 
		state 
		, term 
		, rate 
		, systemsize_bin
		, programfee_bin
		, fund_month 
		, total_funded_loans
		, total_serv_loans
		, delinquency_bin
		, loans_by_delinquency
		--Calculate the # of loans of the previous record (prev. delinquency category) from loans by delinquency column
		, LAG(loans_by_delinquency,1) 
				over (partition by fund_month, state, term, rate, systemsize_bin, programfee_bin
				order by fund_month, state, term, rate, systemsize_bin, programfee_bin, delinquency_bin) as loans_prv_delinquency
	from table_loans_by_cohort
;

select * from table_del_wt_lag
order by fund_month, state, term, rate, systemsize_bin, programfee_bin, delinquency_bin;	
	
--Step 4: Calculate roll rates for each cohort and by delinquency category (with necessary dimensions/filters)
drop table table_roll_rates;
create temp table table_roll_rates as 
	select 
		a.fund_month 
		, a.state
		, a.term 
		, a.rate
		, a.systemsize_bin
		, a.programfee_bin
		, a.total_funded_loans
		, a.total_serv_loans 
		, a.delinquency_bin
		, a.loans_by_delinquency
		, a.loans_prv_delinquency
		, coalesce(round((cast(a.loans_by_delinquency as decimal)/ cast(a.loans_prv_delinquency as decimal))*100,2),0) as roll_rate_pct
	from table_del_wt_lag as a 
;

select * from table_roll_rates;
-- 1464 rows 

select a.delinquency_bin,count(a.delinquency_bin)
from table_roll_rates as a
group by 1
order by 1;

-- To focus our analysis & dashboard on bad-debt, we filter out data with rows containing no delinquency
select * from table_roll_rates as a
where a.delinquency_bin <> '0';
-- 34 rows
