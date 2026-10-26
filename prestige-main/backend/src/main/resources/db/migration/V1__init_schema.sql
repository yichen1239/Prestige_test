-- =====================================================================
-- Renovation / Interior Designer matching platform
-- MySQL 8.0.16 or later (CHECK constraints are only enforced from 8.0.16)
-- Suggested location: backend/src/main/resources/db/migration/V1__init_schema.sql
-- Source: class diagram v3 (after review) + PRD v1.1
-- All ids and foreign keys are INT (Java Integer), matching the class diagram.
--
-- Notes
--  * Timestamps are stored as UTC. Set the JDBC URL option serverTimezone=UTC and
--    spring.jpa.properties.hibernate.jdbc.time_zone=UTC. Dates that define "a day"
--    (idp_view.view_date, availability_date) are computed by the application
--    in the Asia/Singapore time zone.
--  * Enumerations are VARCHAR + CHECK (not MySQL ENUM) so Hibernate's
--    ddl-auto=validate accepts them when mapped with @Enumerated(EnumType.STRING).
--  * PlatformReport is NOT a table: reports are computed on demand.
--  * No ON DELETE / ON UPDATE actions are used (soft delete is used instead).
-- =====================================================================

-- ---------- 1. USERS ------------------------------------------------
CREATE TABLE users (
    user_id        INT       NOT NULL AUTO_INCREMENT,
    name           VARCHAR(100) NOT NULL,                       -- full name, NOT unique
    email          VARCHAR(255) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,                       -- BCrypt hash
    phone          VARCHAR(30)  NULL,
    role           VARCHAR(30)  NOT NULL,
    status         VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    deleted        TINYINT(1)   NOT NULL DEFAULT 0,             -- soft delete (email stays reserved)
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_role_status (role, status, deleted),
    KEY idx_users_name (name),
    CONSTRAINT chk_users_role   CHECK (role IN ('USER_ADMIN','INTERIOR_DESIGNER','CUSTOMER','PLATFORM_MANAGEMENT')),
    CONSTRAINT chk_users_status CHECK (status IN ('ACTIVE','SUSPENDED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 2. DESIGNER PROFILE (InteriorDesigner extras, 1:1 with users) ----
CREATE TABLE designer_profile (
    user_id           INT        NOT NULL,                   -- same value as users.user_id
    bio               VARCHAR(2000) NULL,
    years_experience  INT           NULL,
    specialisation    VARCHAR(150)  NULL,
    updated_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_profile_user FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT chk_profile_years CHECK (years_experience IS NULL OR years_experience BETWEEN 0 AND 80)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 3. COMPANY (one per designer) ---------------------------
CREATE TABLE company (
    company_id       INT       NOT NULL AUTO_INCREMENT,
    designer_id      INT       NOT NULL,
    company_name     VARCHAR(150) NOT NULL,
    registration_no  VARCHAR(50)  NULL,                         -- text: may contain letters
    description      TEXT         NULL,
    address          VARCHAR(255) NULL,
    contact_email    VARCHAR(255) NULL,
    contact_phone    VARCHAR(30)  NULL,
    website          VARCHAR(255) NULL,
    logo_url         VARCHAR(500) NULL,                         -- relative file path served by /api/files
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (company_id),
    UNIQUE KEY uq_company_designer (designer_id),               -- enforces one-to-one
    KEY idx_company_name (company_name),
    CONSTRAINT fk_company_designer FOREIGN KEY (designer_id) REFERENCES users (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 4. CATEGORY ---------------------------------------------
CREATE TABLE category (
    category_id    INT       NOT NULL AUTO_INCREMENT,
    category_name  VARCHAR(100) NOT NULL,                       -- default collation is case-insensitive
    description    VARCHAR(500) NULL,
    active         TINYINT(1)   NOT NULL DEFAULT 1,             -- deactivate instead of delete when in use
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_category_name (category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 5. INTERIOR DESIGN PROJECT (IDP) ------------------------
CREATE TABLE interior_design_project (
    idp_id          INT        NOT NULL AUTO_INCREMENT,
    designer_id     INT        NOT NULL,                     -- NOT unique: one designer, many IDPs
    category_id     INT        NOT NULL,
    title           VARCHAR(150)  NOT NULL,
    description     TEXT          NULL,
    project_status  VARCHAR(20)   NOT NULL,
    budget          DECIMAL(12,2) NULL,                         -- SGD
    start_date      DATE          NULL,
    end_date        DATE          NULL,
    location        VARCHAR(150)  NULL,
    deleted         TINYINT(1)    NOT NULL DEFAULT 0,           -- soft delete
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (idp_id),
    UNIQUE KEY uq_idp_id_designer (idp_id, designer_id),        -- lets rating reference (idp, designer) together
    KEY idx_idp_designer (designer_id, deleted),
    KEY idx_idp_category (category_id, deleted),
    KEY idx_idp_status   (project_status, deleted),
    KEY idx_idp_budget   (budget),
    KEY idx_idp_created  (created_at),
    CONSTRAINT fk_idp_designer FOREIGN KEY (designer_id) REFERENCES users (user_id),
    CONSTRAINT fk_idp_category FOREIGN KEY (category_id) REFERENCES category (category_id),
    CONSTRAINT chk_idp_status  CHECK (project_status IN ('CURRENT','COMPLETED')),
    CONSTRAINT chk_idp_budget  CHECK (budget IS NULL OR budget >= 0),
    CONSTRAINT chk_idp_dates   CHECK (start_date IS NULL OR end_date IS NULL OR end_date >= start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 6. IDP IMAGE --------------------------------------------
-- At most one cover image per IDP (cover_idp_id is NULL for non-covers; NULLs do not collide).
-- When changing the cover, un-set the old cover first (and flush) before setting the new one.
CREATE TABLE idp_image (
    image_id       INT       NOT NULL AUTO_INCREMENT,
    idp_id         INT       NOT NULL,
    image_url      VARCHAR(500) NOT NULL,                       -- relative file path served by /api/files
    caption        VARCHAR(255) NULL,
    display_order  INT          NOT NULL DEFAULT 0,
    is_cover       TINYINT(1)   NOT NULL DEFAULT 0,
    cover_idp_id   INT GENERATED ALWAYS AS (CASE WHEN is_cover = 1 THEN idp_id ELSE NULL END) STORED,
    PRIMARY KEY (image_id),
    UNIQUE KEY uq_one_cover_per_idp (cover_idp_id),
    KEY idx_image_idp (idp_id, display_order),
    CONSTRAINT fk_image_idp FOREIGN KEY (idp_id) REFERENCES interior_design_project (idp_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 7. FAVOURITE (current shortlist) ------------------------
CREATE TABLE favourite (
    customer_id  INT   NOT NULL,
    idp_id       INT   NOT NULL,
    saved_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id, idp_id),                          -- composite key: no duplicates
    KEY idx_fav_idp (idp_id, saved_at),
    KEY idx_fav_saved (saved_at),
    CONSTRAINT fk_fav_customer FOREIGN KEY (customer_id) REFERENCES users (user_id),
    CONSTRAINT fk_fav_idp      FOREIGN KEY (idp_id)      REFERENCES interior_design_project (idp_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 8. IDP VIEW (logged-in customers only) ------------------
-- Record with: INSERT IGNORE INTO idp_view (idp_id, customer_id, view_date) VALUES (?, ?, ?)
CREATE TABLE idp_view (
    view_id      INT   NOT NULL AUTO_INCREMENT,
    idp_id       INT   NOT NULL,
    customer_id  INT   NOT NULL,
    view_date    DATE     NOT NULL,                             -- the day (Asia/Singapore), set by the app
    view_time    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (view_id),
    UNIQUE KEY uq_view_once_per_day (customer_id, idp_id, view_date),
    KEY idx_view_idp_date (idp_id, view_date),
    KEY idx_view_date (view_date),
    CONSTRAINT fk_view_idp      FOREIGN KEY (idp_id)      REFERENCES interior_design_project (idp_id),
    CONSTRAINT fk_view_customer FOREIGN KEY (customer_id) REFERENCES users (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 9. ENQUIRY ----------------------------------------------
CREATE TABLE enquiry (
    enquiry_id   INT        NOT NULL AUTO_INCREMENT,
    idp_id       INT        NOT NULL,
    customer_id  INT        NOT NULL,
    message      VARCHAR(2000) NOT NULL,
    status       VARCHAR(10)   NOT NULL DEFAULT 'NEW',
    created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    read_at      DATETIME      NULL,
    replied_at   DATETIME      NULL,
    PRIMARY KEY (enquiry_id),
    KEY idx_enquiry_idp_status (idp_id, status, created_at),
    KEY idx_enquiry_customer (customer_id),
    KEY idx_enquiry_created (created_at),
    CONSTRAINT fk_enquiry_idp      FOREIGN KEY (idp_id)      REFERENCES interior_design_project (idp_id),
    CONSTRAINT fk_enquiry_customer FOREIGN KEY (customer_id) REFERENCES users (user_id),
    CONSTRAINT chk_enquiry_status  CHECK (status IN ('NEW','READ','REPLIED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 10. RATING ----------------------------------------------
-- Rules enforced here:
--   * one rating per customer per IDP            -> uq_rating_per_idp
--   * one general rating (no IDP) per customer per designer -> uq_rating_general
--   * if idp_id is set it must belong to designer_id         -> fk_rating_idp_designer
CREATE TABLE rating (
    rating_id            INT       NOT NULL AUTO_INCREMENT,
    customer_id          INT       NOT NULL,
    designer_id          INT       NOT NULL,
    idp_id               INT       NULL,
    score                TINYINT      NOT NULL,
    `comment`            VARCHAR(1000) NULL,
    created_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    general_designer_id  INT GENERATED ALWAYS AS (CASE WHEN idp_id IS NULL THEN designer_id ELSE NULL END) STORED,
    PRIMARY KEY (rating_id),
    UNIQUE KEY uq_rating_per_idp  (customer_id, idp_id),
    UNIQUE KEY uq_rating_general  (customer_id, general_designer_id),
    KEY idx_rating_designer (designer_id, created_at),
    KEY idx_rating_idp (idp_id),
    CONSTRAINT fk_rating_customer      FOREIGN KEY (customer_id) REFERENCES users (user_id),
    CONSTRAINT fk_rating_designer      FOREIGN KEY (designer_id) REFERENCES users (user_id),
    CONSTRAINT fk_rating_idp_designer  FOREIGN KEY (idp_id, designer_id)
        REFERENCES interior_design_project (idp_id, designer_id),
    CONSTRAINT chk_rating_score CHECK (score BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 11. AVAILABILITY ----------------------------------------
-- A date with no row is treated as AVAILABLE. Past dates are rejected by the service layer.
CREATE TABLE availability (
    availability_id    INT      NOT NULL AUTO_INCREMENT,
    designer_id        INT      NOT NULL,
    availability_date  DATE        NOT NULL,
    status             VARCHAR(15) NOT NULL,
    created_at         DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (availability_id),
    UNIQUE KEY uq_availability_designer_date (designer_id, availability_date),
    CONSTRAINT fk_availability_designer FOREIGN KEY (designer_id) REFERENCES users (user_id),
    CONSTRAINT chk_availability_status  CHECK (status IN ('AVAILABLE','UNAVAILABLE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 12. ISSUE REPORT ----------------------------------------
-- reporter must be a CUSTOMER or INTERIOR_DESIGNER and handled_by a USER_ADMIN (checked in the service layer).
CREATE TABLE issue_report (
    report_id           INT        NOT NULL AUTO_INCREMENT,
    reporter_id         INT        NOT NULL,
    handled_by          INT        NULL,
    issue_type          VARCHAR(20)   NOT NULL,
    target_idp_id       INT        NULL,
    target_designer_id  INT        NULL,
    title               VARCHAR(150)  NOT NULL,
    description         VARCHAR(2000) NOT NULL,
    status              VARCHAR(10)   NOT NULL DEFAULT 'OPEN',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    rectified_at        DATETIME      NULL,
    PRIMARY KEY (report_id),
    KEY idx_report_reporter (reporter_id, created_at),
    KEY idx_report_status (status, created_at),
    KEY idx_report_type (issue_type),
    CONSTRAINT fk_report_reporter FOREIGN KEY (reporter_id)        REFERENCES users (user_id),
    CONSTRAINT fk_report_handler  FOREIGN KEY (handled_by)         REFERENCES users (user_id),
    CONSTRAINT fk_report_idp      FOREIGN KEY (target_idp_id)      REFERENCES interior_design_project (idp_id),
    CONSTRAINT fk_report_designer FOREIGN KEY (target_designer_id) REFERENCES users (user_id),
    CONSTRAINT chk_report_type   CHECK (issue_type IN ('IDP_OR_DESIGNER','PLATFORM_ISSUE')),
    CONSTRAINT chk_report_status CHECK (status IN ('OPEN','RECTIFIED')),
    CONSTRAINT chk_report_target CHECK (issue_type <> 'IDP_OR_DESIGNER' OR target_idp_id IS NOT NULL OR target_designer_id IS NOT NULL),
    CONSTRAINT chk_report_rectified CHECK (status <> 'RECTIFIED' OR (handled_by IS NOT NULL AND rectified_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- No seed rows here. The initial USER_ADMIN is created by the application at first startup
-- from APP_ADMIN_EMAIL / APP_ADMIN_PASSWORD; demo categories belong in the dev-profile seeder.
