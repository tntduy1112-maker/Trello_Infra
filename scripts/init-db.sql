-- ============================================
-- TaskFlow — Database Initialization
-- ============================================
-- This script runs on first PostgreSQL startup
-- ============================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";      -- Fuzzy text search
CREATE EXTENSION IF NOT EXISTS "btree_gin";    -- GIN index support

-- Create custom types (ENUMs)
DO $$ BEGIN
    CREATE TYPE org_role AS ENUM ('owner', 'admin', 'member');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE board_role AS ENUM ('owner', 'admin', 'member', 'viewer');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE board_visibility AS ENUM ('private', 'workspace', 'public');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE card_priority AS ENUM ('none', 'low', 'medium', 'high');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'declined', 'expired');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE notification_type AS ENUM (
        'card_assigned',
        'card_due_soon',
        'card_overdue',
        'comment_added',
        'comment_reply',
        'mentioned',
        'board_invitation',
        'checklist_item_assigned'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE activity_action AS ENUM (
        'card_created', 'card_updated', 'card_moved', 'card_archived', 'card_deleted',
        'card_assigned', 'card_unassigned', 'card_completed', 'card_reopened',
        'card_due_date_set', 'card_due_date_removed',
        'list_created', 'list_renamed', 'list_moved', 'list_archived',
        'label_added', 'label_removed',
        'checklist_created', 'checklist_deleted',
        'checklist_item_completed', 'checklist_item_uncompleted',
        'comment_added', 'comment_edited', 'comment_deleted',
        'attachment_added', 'attachment_deleted', 'cover_set', 'cover_removed',
        'member_added', 'member_removed'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Grant privileges (for application user if different from postgres)
-- GRANT ALL PRIVILEGES ON DATABASE taskflow TO taskflow;
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO taskflow;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO taskflow;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'TaskFlow database initialized successfully at %', NOW();
END $$;
