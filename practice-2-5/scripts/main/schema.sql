SET ROLE admin;
CREATE SCHEMA IF NOT EXISTS company;

--Админ имеет доступ к специальным функциям, например, может изменить
-- автора задания или внести изменения в завершенное задание.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA company to admin;

SET SCHEMA 'company';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employee_role') THEN
        CREATE TYPE company.employee_role as ENUM ('manager', 'ranker');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority') THEN
        CREATE TYPE company.priority as ENUM ('low', 'medium', 'high');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'equip_status') THEN
        CREATE TYPE company.equip_status as ENUM ('accepted', 'progress', 'completed', 'terminated');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'client_type') THEN
        CREATE TYPE company.client_type as ENUM ('current', 'potential');
    END IF;
END$$;

CREATE TABLE IF NOT EXISTS company.organization(
    ogrnip bigserial primary key UNIQUE NOT NULL,
    org_name varchar,
    type_activity varchar,
    address text
);

CREATE TABLE IF NOT EXISTS company.clients
(
    passport bigserial primary key UNIQUE NOT NULL,
    phone varchar NOT NULL,
    ogrnip bigserial references company.organization(ogrnip) NOT NULL,
    "type" client_type NOT NULL,
    "name" varchar,
    email varchar
);

CREATE TABLE IF NOT EXISTS company.employees (
    passport bigserial primary key UNIQUE NOT NULL,
    username varchar NOT NULL,
    "role" employee_role NOT NULL,
    phone varchar NOT NULL,
    email varchar
);

CREATE TABLE IF NOT EXISTS company.task (
    task_id bigserial primary key UNIQUE                               NOT NULL,

    customer_passport bigserial references company.clients(passport)   NOT NULL,
    author_passport bigserial references company.employees(passport)   NOT NULL,
    executor_passport bigserial references company.employees(passport) NOT NULL,

    create_date timestamp without time zone                            NOT NULL,
    deadline_date timestamp without time zone,
    completion_date timestamp without time zone,

    priority priority                                                  NOT NULL,
    descriptions text
);

CREATE TABLE IF NOT EXISTS company.equipment (
    item_id bigserial primary key UNIQUE NOT NULL,

    "name" varchar NOT NULL,
    weight real,
    volume real,

    status equip_status NOT NULL
);

CREATE TABLE IF NOT EXISTS company.contract (
    contract_id bigserial primary key UNIQUE NOT NULL,
    task_id bigserial references company.task(task_id) NOT NULL,
    equipment_id bigserial references company.equipment(item_id) NOT NULL,

    create_date timestamp without time zone,
    completion_date timestamp without time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS company.report(
    report_id uuid primary key UNIQUE NOT NULL,
    employee_id bigint references company.employees(passport),

    total_number_employee_tasks_in_period bigint,
    number_employee_tasks_completed_on_time bigint,
    number_employee_tasks_not_completed_on_time bigint,
    number_employee_tasks_unfinished bigint,
    number_employee_tasks_unfinished_that_not_expired bigint,

    start_period timestamp,
    end_period timestamp,
    create_date timestamp
);

