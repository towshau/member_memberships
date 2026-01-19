# Member Memberships Table Documentation

## Overview

The `member_memberships` table is a core table in the database that tracks membership periods, stages, and staff assignments for each member. It serves as a central record for all membership-related information, linking members to their membership types, coaches, and various metadata.

**Table Comment:** Tracks membership periods, stages, and staff assignments for each member.

**Row Count:** 1,438 records

## Table Structure

### Primary Key
- `id` (uuid) - Unique identifier for this membership record

### Core Membership Fields
- `member_id` (uuid) - Foreign key to `member_database.id` identifying the member
- `membership_type_id` (uuid) - Foreign key to `membership_types.id` defining which type of membership (3, 6, 12 months, etc.)
- `start_date` (date) - Start date of the membership period
- `end_date` (date) - End date of the membership period
- `status` (text) - Current membership status (e.g., pending, active, cancelled). Default: 'pending'
- `membership_stage` (text) - Pipeline stage label for the membership lifecycle (e.g., new, renewal, expired)
- `journey_stage` (journey_stage_type enum) - Member's lifecycle stage (e.g., first_30, booked, renewed_member)

### Staff Assignments
- `coach_id` (uuid) - Primary coach assigned to the member (FK to `staff_database.id`)
- `salesperson_id` (uuid) - Staff member who originally sold the membership
- `programming_coach_id` (uuid) - Coach responsible for programming/training plans
- `handoff_coach_id` (uuid) - Coach responsible for onboarding/handoff
- `revenue_team_assignee` (uuid) - Revenue team staff member assigned to oversee membership renewal/revenue
- `renewal_assignee` (uuid) - Staff member responsible for executing renewal
- `nutrition_lead` (uuid) - Nutrition coach assigned to the member

### Metadata References
- `newsale_metadata` (uuid) - FK to `member_newsale_metadata.id` for original sale metadata
- `renewal_metadata` (uuid) - FK to `member_renewal_meta.id` for renewal metadata

### Additional Fields
- `gym` (text) - Gym location for the membership (e.g., Bridge Street, Bligh Street)
- `test_duration` (text) - Optional trial/test duration field
- `member_name` (text) - Denormalized copy of the member's name (for convenience)
- `coach_name` (text) - Denormalized coach name (for convenience)
- `pipeline_lost` (pipelinelost_churnmarker enum) - Churn marker (good_churn, bad_churn)
- `membership_notes` (text) - Additional notes about the membership
- `primary_membership_id` (uuid) - Self-referencing foreign key for hierarchical membership relationships
- `created_at` (timestamptz) - Timestamp when this record was created

## Database Diagram

erDiagram
    member_memberships {
        uuid id PK
        uuid member_id FK
        uuid membership_type_id FK
        date start_date
        date end_date
        text status
        text membership_stage
        journey_stage_type journey_stage
        uuid coach_id FK
        uuid salesperson_id FK
        uuid programming_coach_id FK
        uuid handoff_coach_id FK
        uuid revenue_team_assignee FK
        uuid renewal_assignee FK
        uuid nutrition_lead FK
        uuid newsale_metadata FK
        uuid renewal_metadata FK
        uuid primary_membership_id FK
        text gym
        text membership_notes
        timestamptz created_at
    }
    
    member_database {
        uuid id PK
        text first_name
        text last_name
        text email
    }
    
    membership_types {
        uuid id PK
        text name
        membership_category_enum category
    }
    
    staff_database {
        uuid id PK
        text first_name
        text last_name
    }
    
    member_newsale_metadata {
        uuid id PK
        uuid member_id FK
        numeric price_paid
    }
    
    member_renewal_meta {
        uuid id PK
        uuid member_id FK
        numeric price_paid
    }
    
    member_addons {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_programs {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_biomap {
        uuid task_id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_not_renewing {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_holds {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_vo2credits {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    stripe_invoices {
        uuid id PK
        uuid membership_id FK
        uuid member_id FK
    }
    
    member_myzone {
        uuid id PK
        uuid initial_membership FK
        uuid member_id FK
    }

    member_memberships ||--|| member_database : "belongs to"
    member_memberships ||--|| membership_types : "has type"
    member_memberships ||--o| staff_database : "has coach"
    member_memberships ||--o| staff_database : "has salesperson"
    member_memberships ||--o| staff_database : "has programming_coach"
    member_memberships ||--o| staff_database : "has handoff_coach"
    member_memberships ||--o| staff_database : "has revenue_team_assignee"
    member_memberships ||--o| staff_database : "has renewal_assignee"
    member_memberships ||--o| staff_database : "has nutrition_lead"
    member_memberships ||--o| member_newsale_metadata : "references"
    member_memberships ||--o| member_renewal_meta : "references"
    member_memberships ||--o{ member_memberships : "has primary"
    member_memberships ||--o{ member_addons : "has"
    member_memberships ||--o{ member_programs : "has"
    member_memberships ||--o{ member_biomap : "has"
    member_memberships ||--o| member_not_renewing : "may have"
    member_memberships ||--o{ member_holds : "has"
    member_memberships ||--o{ member_vo2credits : "has"
    member_memberships ||--o{ stripe_invoices : "has"
    member_memberships ||--o{ member_myzone : "is initial for"
