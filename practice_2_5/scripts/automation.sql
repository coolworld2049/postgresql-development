SET ROLE admin
\connect client_management;
SET SCHEMA 'company';

--------------------------------------------------------INDEX-----------------------------------------------------------
CREATE INDEX organization_address_index ON company.organization USING btree (address);
CREATE INDEX organization_org_name_index ON company.organization USING btree (org_name);
CREATE INDEX client_name_index ON company.clients USING btree (username);


--------------------------------------------------------TRIGGER---------------------------------------------------------
CREATE OR REPLACE FUNCTION delete_old_rows() RETURNS trigger LANGUAGE plpgsql AS
$BODY$
BEGIN
    DELETE FROM company.task WHERE completion_date < localtimestamp - '1 year'::interval;
    RETURN NULL;
END;
$BODY$;

--По прошествии 12 месяцев после даты завершения задания сведения о нем удаляются из системы.
CREATE OR REPLACE TRIGGER task_mgmt BEFORE INSERT OR UPDATE ON company.task
    FOR EACH STATEMENT EXECUTE PROCEDURE delete_old_rows();

--------------------------------------------------------REPORT----------------------------------------------------------
SET ROLE postgres;

-- общее количество заданий для данного сотрудника в указанный период
CREATE OR REPLACE FUNCTION total_number_employee_tasks_in_period
    (start_timestamp timestamp , end_timestamp timestamp , employee_passport bigint)
    RETURNS bigint LANGUAGE plpgsql AS
$BODY$
BEGIN
    RETURN (SELECT count(*) FROM company.task WHERE executor_passport = employee_passport
                                                     or author_passport = employee_passport
                                                  and create_date BETWEEN start_timestamp and end_timestamp);
END;
$BODY$;

-- сколько заданий завершено вовремя
CREATE OR REPLACE FUNCTION number_employee_tasks_completed_on_time
    (start_timestamp timestamp , end_timestamp timestamp , employee_passport bigint)
    RETURNS bigint LANGUAGE plpgsql AS
$BODY$
BEGIN
    RETURN (SELECT count(*) FROM company.task WHERE executor_passport = employee_passport
                                                     or author_passport = employee_passport
                                                            and deadline_date::timestamp >= completion_date::timestamp
                                                            and create_date BETWEEN start_timestamp and end_timestamp);
END;
$BODY$;

-- сколько заданий завершено с нарушением срока исполнения
CREATE OR REPLACE FUNCTION number_employee_tasks_not_completed_on_time
    (start_timestamp timestamp , end_timestamp timestamp , employee_passport bigint)
    RETURNS bigint LANGUAGE plpgsql AS
$BODY$
BEGIN
    RETURN (SELECT count(*) FROM company.task WHERE executor_passport = employee_passport
                                                     or author_passport = employee_passport
                                                            and deadline_date::timestamp < completion_date::timestamp
                                                            and create_date BETWEEN start_timestamp and end_timestamp);
END;
$BODY$;

-- сколько заданий с истекшим сроком исполнения не завершено
CREATE OR REPLACE FUNCTION number_employee_tasks_unfinished
    (start_timestamp timestamp , end_timestamp timestamp , employee_passport bigint)
    RETURNS bigint LANGUAGE plpgsql AS
$BODY$
BEGIN
    RETURN (SELECT count(*) FROM company.task WHERE executor_passport = employee_passport
                                                     or author_passport = employee_passport
                                                            and current_timestamp > deadline_date::timestamp
                                                            and completion_date is null
                                                            and create_date BETWEEN start_timestamp and end_timestamp);
END;
$BODY$;


-- сколько не завершенных заданий, срок исполнения которых не истек
CREATE OR REPLACE FUNCTION number_employee_tasks_unfinished_that_not_expired
    (start_timestamp timestamp , end_timestamp timestamp , employee_passport bigint)
    RETURNS bigint LANGUAGE plpgsql AS
$BODY$
BEGIN
    RETURN (SELECT count(*) FROM company.task WHERE executor_passport = employee_passport
                                                     or author_passport = employee_passport
                                                            and current_timestamp < deadline_date::timestamp
                                                            and completion_date is null
                                                            and create_date BETWEEN start_timestamp and end_timestamp);
END;
$BODY$;

-- Система генерирует отчет по исполнению заданий каким-либо сотрудником
-- в течение периода времени, указываемого в параметре отчета.
CREATE OR REPLACE FUNCTION generate_report_by_period_and_employee(start_timestamp timestamp , end_timestamp timestamp, employee_passport bigint)
    RETURNS RECORD LANGUAGE plpgsql AS
$BODY$
DECLARE
    report RECORD;
BEGIN
    SELECT gen_random_uuid(),
            employee_passport,
            total_number_employee_tasks_in_period(start_timestamp, end_timestamp, employee_passport),
            number_employee_tasks_completed_on_time(start_timestamp, end_timestamp, employee_passport),
            number_employee_tasks_not_completed_on_time(start_timestamp, end_timestamp, employee_passport),
            number_employee_tasks_unfinished(start_timestamp, end_timestamp, employee_passport),
            number_employee_tasks_unfinished_that_not_expired(start_timestamp, end_timestamp, employee_passport),
            "start_timestamp",
            "end_timestamp",
            localtimestamp INTO report;
    RETURN report;
END;
$BODY$;

CREATE OR REPLACE FUNCTION generate_report_for_all_employees(start_timestamp timestamp , end_timestamp timestamp)
    RETURNS TABLE (employee_id bigint,
                    total_number_employee_tasks_in_period bigint,
                    number_employee_tasks_completed_on_time bigint,
                    number_employee_tasks_not_completed_on_time bigint,
                    number_employee_tasks_unfinished bigint,
                    number_employee_tasks_unfinished_that_not_expired bigint,
                    period json,
                    create_date timestamp) LANGUAGE plpgsql AS $BODY$
    DECLARE ctm timestamp = current_timestamp;
    DECLARE filter_by json = json_build_object(
        'start_timestamp',start_timestamp,
        'end_timestamp', end_timestamp
        );
BEGIN
    RETURN QUERY
        SELECT passport,
                total_number_employee_tasks_in_period(start_timestamp, end_timestamp, passport),
                number_employee_tasks_completed_on_time(start_timestamp, end_timestamp, passport),
                number_employee_tasks_not_completed_on_time(start_timestamp, end_timestamp, passport),
                number_employee_tasks_unfinished(start_timestamp, end_timestamp, passport),
                number_employee_tasks_unfinished_that_not_expired(start_timestamp, end_timestamp, passport),
                filter_by,
                ctm FROM company.employees;
END;
$BODY$;


COPY (SELECT * FROM generate_report_for_all_employees('2022-07-01 04:05:06'::timestamp,
    '2022-11-01 04:05:06'::timestamp))
    TO '/temp/report.csv' DELIMITER ',' CSV HEADER;

COPY (SELECT row_to_json(results) FROM generate_report_for_all_employees('2022-07-01 04:05:06'::timestamp,
    '2022-11-01 04:05:06'::timestamp) as results) TO '/temp/report.json'
    WITH (FORMAT text, HEADER FALSE);

COPY (SELECT row_to_json(results) FROM company.clients as results) TO '/temp/clients.json' WITH (FORMAT text, HEADER FALSE);
COPY (SELECT row_to_json(results) FROM company.employees as results) TO '/temp/employees.json' WITH (FORMAT text, HEADER FALSE);
COPY (SELECT row_to_json(results) FROM company.task as results) TO '/temp/task.json' WITH (FORMAT text, HEADER FALSE);