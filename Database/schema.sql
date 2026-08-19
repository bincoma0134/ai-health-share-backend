--
-- PostgreSQL database dump
--

\restrict GXMLBytf23mtjvtlVgrnpPwgXuO9lDMJsAHaBXes79njQj04cBaUh9Ud90LGGUZ

-- Dumped from database version 16.15 (651533a)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: neon_auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA neon_auth;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: affiliate_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.affiliate_status_enum AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED'
);


--
-- Name: payment_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_status_enum AS ENUM (
    'UNPAID',
    'PAID_ESCROW',
    'REFUNDED',
    'REVENUE_SPLIT',
    'PAID',
    'TOPUP_UNPAID',
    'TOPUP_PAID'
);


--
-- Name: service_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_status_enum AS ENUM (
    'PENDING',
    'CHECKED_IN',
    'COMPLETED',
    'DISPUTED',
    'CANCELLED'
);


--
-- Name: service_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_type_enum AS ENUM (
    'SINGLE_SESSION',
    'PACKAGE',
    'LONG_TERM',
    'RELAXATION',
    'TREATMENT'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'USER',
    'CREATOR',
    'PARTNER_ADMIN',
    'SUPER_ADMIN',
    'MODERATOR'
);


--
-- Name: user_voucher_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_voucher_status AS ENUM (
    'UNUSED',
    'LOCKED',
    'USED'
);


--
-- Name: verification_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.verification_status_enum AS ENUM (
    'PENDING',
    'VERIFIED',
    'REJECTED'
);


--
-- Name: voucher_discount_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.voucher_discount_type AS ENUM (
    'PERCENTAGE',
    'FIXED_AMOUNT'
);


--
-- Name: voucher_issuer_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.voucher_issuer_type AS ENUM (
    'ADMIN',
    'PARTNER'
);


--
-- Name: voucher_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.voucher_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'INACTIVE'
);


--
-- Name: withdrawal_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.withdrawal_status_enum AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'COMPLETED'
);


--
-- Name: sync_service_video_to_tiktok_feeds(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_service_video_to_tiktok_feeds() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Kiểm tra nếu trạng thái chuyển sang APPROVED và dịch vụ đó có chứa video_url
    IF NEW.status::text = 'APPROVED' 
       AND (OLD.status::text IS DISTINCT FROM 'APPROVED')
       AND NEW.video_url IS NOT NULL 
       AND NEW.video_url != '' THEN
        
        INSERT INTO tiktok_feeds (author_id, title, content, video_url, price, status, created_at, updated_at)
        VALUES (NEW.partner_id, NEW.service_name, NEW.description, NEW.video_url, NEW.price, 'APPROVED', NOW(), NOW());
        
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: update_followers_count(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_followers_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE public.users 
        SET followers_count = followers_count + 1 
        WHERE id = NEW.following_id;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE public.users 
        SET followers_count = GREATEST(0, followers_count - 1) 
        WHERE id = OLD.following_id;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: update_wallet_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_wallet_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.account (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "accountId" text NOT NULL,
    "providerId" text NOT NULL,
    "userId" uuid NOT NULL,
    "accessToken" text,
    "refreshToken" text,
    "idToken" text,
    "accessTokenExpiresAt" timestamp with time zone,
    "refreshTokenExpiresAt" timestamp with time zone,
    scope text,
    password text,
    "createdAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp with time zone NOT NULL
);


--
-- Name: invitation; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.invitation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "organizationId" uuid NOT NULL,
    email text NOT NULL,
    role text,
    status text NOT NULL,
    "expiresAt" timestamp with time zone NOT NULL,
    "createdAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "inviterId" uuid NOT NULL
);


--
-- Name: jwks; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.jwks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "publicKey" text NOT NULL,
    "privateKey" text NOT NULL,
    "createdAt" timestamp with time zone NOT NULL,
    "expiresAt" timestamp with time zone
);


--
-- Name: member; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.member (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "organizationId" uuid NOT NULL,
    "userId" uuid NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp with time zone NOT NULL
);


--
-- Name: organization; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.organization (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    logo text,
    "createdAt" timestamp with time zone NOT NULL,
    metadata text
);


--
-- Name: project_config; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.project_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    endpoint_id text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    trusted_origins jsonb NOT NULL,
    social_providers jsonb NOT NULL,
    email_provider jsonb,
    email_and_password jsonb,
    allow_localhost boolean NOT NULL,
    plugin_configs jsonb,
    webhook_config jsonb
);


--
-- Name: session; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.session (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "expiresAt" timestamp with time zone NOT NULL,
    token text NOT NULL,
    "createdAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp with time zone NOT NULL,
    "ipAddress" text,
    "userAgent" text,
    "userId" uuid NOT NULL,
    "impersonatedBy" text,
    "activeOrganizationId" text
);


--
-- Name: user; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth."user" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    "emailVerified" boolean NOT NULL,
    image text,
    "createdAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    role text,
    banned boolean,
    "banReason" text,
    "banExpires" timestamp with time zone
);


--
-- Name: verification; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.verification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    identifier text NOT NULL,
    value text NOT NULL,
    "expiresAt" timestamp with time zone NOT NULL,
    "createdAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: affiliate_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.affiliate_metrics (
    partnership_id uuid NOT NULL,
    total_clicks integer DEFAULT 0 NOT NULL,
    total_conversions integer DEFAULT 0 NOT NULL,
    total_revenue_generated numeric(15,2) DEFAULT 0.00,
    total_commission_earned numeric(15,2) DEFAULT 0.00,
    last_activity_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: affiliate_partnerships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.affiliate_partnerships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    creator_id uuid NOT NULL,
    partner_id uuid NOT NULL,
    status public.affiliate_status_enum DEFAULT 'PENDING'::public.affiliate_status_enum NOT NULL,
    admin_note text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ai_chat_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_chat_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    role text,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    conversation_id uuid NOT NULL,
    CONSTRAINT ai_chat_history_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])))
);


--
-- Name: ai_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text DEFAULT 'Trò chuyện mới'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: ai_support_chat_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_support_chat_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    sender_role character varying(10) NOT NULL,
    message_content text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sender_role CHECK (((sender_role)::text = ANY ((ARRAY['USER'::character varying, 'AI'::character varying])::text[])))
);


--
-- Name: ai_support_conversation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_support_conversation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    partner_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    partner_id uuid NOT NULL,
    service_id uuid,
    video_id uuid,
    booking_id uuid,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    status text DEFAULT 'PENDING'::text,
    note text,
    created_at timestamp with time zone DEFAULT now(),
    check_in_code text,
    user_confirmed boolean DEFAULT false,
    partner_notes text,
    rejection_reason text,
    payment_deadline timestamp with time zone,
    customer_name text,
    customer_phone text,
    affiliate_code text,
    total_amount numeric DEFAULT 0,
    applied_user_voucher_id uuid,
    preferred_time timestamp with time zone,
    guest_count integer DEFAULT 1 NOT NULL,
    CONSTRAINT appointments_guest_count_check CHECK ((guest_count > 0))
);


--
-- Name: bookings_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    service_id uuid,
    affiliate_id uuid,
    total_amount numeric NOT NULL,
    payment_status public.payment_status_enum DEFAULT 'UNPAID'::public.payment_status_enum,
    service_status public.service_status_enum DEFAULT 'PENDING'::public.service_status_enum,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    order_code bigint,
    video_id uuid,
    partner_revenue numeric DEFAULT 0,
    platform_fee numeric DEFAULT 0,
    affiliate_revenue numeric DEFAULT 0,
    customer_name text,
    customer_phone text,
    note text,
    applied_voucher_id uuid,
    voucher_discount_amount numeric(10,2) DEFAULT 0,
    discount_funded_by character varying(20),
    final_paid_amount numeric(10,2) DEFAULT 0,
    CONSTRAINT bookings_transactions_discount_funded_by_check CHECK (((discount_funded_by)::text = ANY ((ARRAY['ADMIN'::character varying, 'PARTNER'::character varying])::text[]))),
    CONSTRAINT chk_discount_funded_by CHECK (((discount_funded_by)::text = ANY ((ARRAY['ADMIN'::character varying, 'PARTNER'::character varying])::text[])))
);


--
-- Name: community_post_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.community_post_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_id uuid,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: community_post_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.community_post_likes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: community_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.community_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    content text NOT NULL,
    image_url text,
    status text DEFAULT 'APPROVED'::text,
    likes_count integer DEFAULT 0,
    comments_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: creator_upgrades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.creator_upgrades (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    reason_answer character varying(255) NOT NULL,
    status character varying(50) DEFAULT 'PENDING'::character varying,
    moderation_note text,
    moderated_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_creator_upgrades_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'DELETED'::character varying])::text[])))
);


--
-- Name: missions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.missions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    mission_type character varying(50) NOT NULL,
    target_value integer DEFAULT 1 NOT NULL,
    reward_points integer DEFAULT 0 NOT NULL,
    status character varying(50) DEFAULT 'ACTIVE'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sender_id uuid,
    category character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    short_message text NOT NULL,
    deep_link_payload jsonb DEFAULT '{}'::jsonb,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    delivery_status character varying(50) DEFAULT 'PENDING'::character varying,
    delivered_at timestamp without time zone
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    appointment_id uuid NOT NULL,
    user_id uuid NOT NULL,
    partner_id uuid NOT NULL,
    service_id uuid,
    rating integer NOT NULL,
    comment text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    partner_id uuid NOT NULL,
    service_name character varying NOT NULL,
    description text,
    price numeric NOT NULL,
    service_type public.service_type_enum DEFAULT 'SINGLE_SESSION'::public.service_type_enum,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying DEFAULT 'PENDING'::character varying,
    moderation_note text,
    moderated_by uuid,
    video_url text,
    tags jsonb DEFAULT '[]'::jsonb,
    thumbnail_url text,
    image_url text,
    is_deleted boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now(),
    affiliate_rate numeric DEFAULT 0,
    capacity_per_service integer DEFAULT 1 NOT NULL,
    CONSTRAINT services_capacity_per_service_check CHECK ((capacity_per_service > 0))
);


--
-- Name: svalue_transaction_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.svalue_transaction_logs (
    id integer NOT NULL,
    user_id character varying(255) NOT NULL,
    action_type character varying(50) NOT NULL,
    points_changed integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    reference_id character varying(255)
);


--
-- Name: svalue_transaction_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.svalue_transaction_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: svalue_transaction_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.svalue_transaction_logs_id_seq OWNED BY public.svalue_transaction_logs.id;


--
-- Name: tiktok_feed_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiktok_feed_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_id uuid,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tiktok_feed_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiktok_feed_likes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tiktok_feed_saves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiktok_feed_saves (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tiktok_feed_shares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiktok_feed_shares (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: tiktok_feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tiktok_feeds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    title text NOT NULL,
    content text,
    video_url text NOT NULL,
    price numeric DEFAULT 0,
    status text DEFAULT 'PENDING'::text,
    likes_count integer DEFAULT 0,
    saves_count integer DEFAULT 0,
    shares_count integer DEFAULT 0,
    comments_count integer DEFAULT 0,
    moderation_note text,
    moderated_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    affiliate_rate numeric DEFAULT 0,
    partner_id uuid,
    service_id uuid,
    voucher_code character varying(255),
    feed_type character varying(50) DEFAULT 'TIKTOK_FEED'::character varying,
    trim_start_percent numeric DEFAULT 0.0,
    trim_end_percent numeric DEFAULT 100.0
);


--
-- Name: user_fcm_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_fcm_tokens (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    token text NOT NULL,
    device_id character varying(255),
    platform character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_fcm_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_fcm_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_fcm_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_fcm_tokens_id_seq OWNED BY public.user_fcm_tokens.id;


--
-- Name: user_follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_follows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    follower_id uuid NOT NULL,
    following_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_missions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_missions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id character varying(255) NOT NULL,
    mission_code character varying(50) NOT NULL,
    current_progress integer DEFAULT 0 NOT NULL,
    status character varying(50) DEFAULT 'IN_PROGRESS'::character varying NOT NULL,
    last_progress_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    completed_at timestamp without time zone
);


--
-- Name: user_svalue_wallet; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_svalue_wallet (
    user_id character varying(255) NOT NULL,
    balance integer DEFAULT 0 NOT NULL,
    streak_count integer DEFAULT 0 NOT NULL,
    last_checkin_at timestamp without time zone,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_vouchers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_vouchers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    voucher_id uuid NOT NULL,
    status character varying(20) DEFAULT 'UNUSED'::character varying,
    locked_until timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT user_vouchers_status_check CHECK (((status)::text = ANY ((ARRAY['UNUSED'::character varying, 'LOCKED'::character varying, 'USED'::character varying])::text[])))
);


--
-- Name: user_wellness_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_wellness_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    mood_state character varying(50) NOT NULL,
    body_focus character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_wellness_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_wellness_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    focus_areas text[],
    total_wellness_minutes integer DEFAULT 0,
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    phone_number character varying,
    role public.user_role DEFAULT 'USER'::public.user_role,
    health_goals text[],
    affiliate_code character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    telegram_chat_id text,
    full_name text,
    bio text,
    avatar_url text,
    cover_url text,
    reputation_points integer DEFAULT 0,
    theme_preference character varying DEFAULT 'dark'::character varying,
    latitude double precision,
    longitude double precision,
    username text,
    phone text,
    social_links jsonb DEFAULT '[]'::jsonb,
    physical_address text,
    followers_count integer DEFAULT 0,
    password_hash text,
    svalue_balance integer DEFAULT 0,
    level integer DEFAULT 1,
    video_count integer DEFAULT 0,
    partner_ai_context text,
    has_claimed_wellness_reward boolean DEFAULT false,
    points_balance numeric(15,2) DEFAULT 0.00 NOT NULL,
    CONSTRAINT users_points_balance_check CHECK ((points_balance >= (0)::numeric))
);


--
-- Name: vouchers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vouchers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    issuer_type character varying(20) NOT NULL,
    issuer_id uuid,
    discount_type character varying(20) NOT NULL,
    discount_value numeric(10,2) NOT NULL,
    max_discount_amount numeric(10,2),
    min_order_value numeric(10,2) DEFAULT 0,
    applicable_services uuid[],
    total_quantity integer NOT NULL,
    used_quantity integer DEFAULT 0,
    valid_from timestamp without time zone NOT NULL,
    valid_until timestamp without time zone NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_vip boolean DEFAULT false NOT NULL,
    point_price numeric(15,2) DEFAULT 0.00 NOT NULL,
    fixed_time_slot character varying(100),
    description text,
    CONSTRAINT chk_discount_logic CHECK (((((discount_type)::text = 'PERCENTAGE'::text) AND (discount_value >= (1)::numeric) AND (discount_value <= (99)::numeric) AND (max_discount_amount IS NOT NULL) AND (max_discount_amount > (0)::numeric)) OR (((discount_type)::text = 'FIXED_AMOUNT'::text) AND (discount_value > (0)::numeric) AND ((max_discount_amount IS NULL) OR (max_discount_amount = discount_value))))),
    CONSTRAINT chk_issuer_type CHECK (((issuer_type)::text = ANY ((ARRAY['ADMIN'::character varying, 'PARTNER'::character varying])::text[]))),
    CONSTRAINT chk_time_logic CHECK ((valid_until > valid_from)),
    CONSTRAINT vouchers_discount_type_check CHECK (((discount_type)::text = ANY ((ARRAY['PERCENTAGE'::character varying, 'FIXED_AMOUNT'::character varying])::text[]))),
    CONSTRAINT vouchers_issuer_type_check CHECK (((issuer_type)::text = ANY ((ARRAY['ADMIN'::character varying, 'PARTNER'::character varying])::text[]))),
    CONSTRAINT vouchers_point_price_check CHECK ((point_price >= (0)::numeric)),
    CONSTRAINT vouchers_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'INACTIVE'::character varying])::text[]))),
    CONSTRAINT vouchers_total_quantity_check CHECK ((total_quantity > 0)),
    CONSTRAINT vouchers_used_quantity_check CHECK ((used_quantity >= 0))
);


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    balance numeric DEFAULT 0 NOT NULL,
    total_earned numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: withdrawal_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.withdrawal_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    amount numeric NOT NULL,
    payout_info jsonb NOT NULL,
    status public.withdrawal_status_enum DEFAULT 'PENDING'::public.withdrawal_status_enum,
    admin_note text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    processed_by uuid,
    CONSTRAINT withdrawal_requests_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: svalue_transaction_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.svalue_transaction_logs ALTER COLUMN id SET DEFAULT nextval('public.svalue_transaction_logs_id_seq'::regclass);


--
-- Name: user_fcm_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens ALTER COLUMN id SET DEFAULT nextval('public.user_fcm_tokens_id_seq'::regclass);


--
-- Name: account account_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.account
    ADD CONSTRAINT account_pkey PRIMARY KEY (id);


--
-- Name: invitation invitation_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.invitation
    ADD CONSTRAINT invitation_pkey PRIMARY KEY (id);


--
-- Name: jwks jwks_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.jwks
    ADD CONSTRAINT jwks_pkey PRIMARY KEY (id);


--
-- Name: member member_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.member
    ADD CONSTRAINT member_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: organization organization_slug_key; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.organization
    ADD CONSTRAINT organization_slug_key UNIQUE (slug);


--
-- Name: project_config project_config_endpoint_id_key; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.project_config
    ADD CONSTRAINT project_config_endpoint_id_key UNIQUE (endpoint_id);


--
-- Name: project_config project_config_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.project_config
    ADD CONSTRAINT project_config_pkey PRIMARY KEY (id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- Name: session session_token_key; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.session
    ADD CONSTRAINT session_token_key UNIQUE (token);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: verification verification_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.verification
    ADD CONSTRAINT verification_pkey PRIMARY KEY (id);


--
-- Name: affiliate_metrics affiliate_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_metrics
    ADD CONSTRAINT affiliate_metrics_pkey PRIMARY KEY (partnership_id);


--
-- Name: affiliate_partnerships affiliate_partnerships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_partnerships
    ADD CONSTRAINT affiliate_partnerships_pkey PRIMARY KEY (id);


--
-- Name: ai_chat_history ai_chat_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_chat_history
    ADD CONSTRAINT ai_chat_history_pkey PRIMARY KEY (id);


--
-- Name: ai_conversations ai_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT ai_conversations_pkey PRIMARY KEY (id);


--
-- Name: ai_support_chat_history ai_support_chat_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_chat_history
    ADD CONSTRAINT ai_support_chat_history_pkey PRIMARY KEY (id);


--
-- Name: ai_support_conversation ai_support_conversation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_conversation
    ADD CONSTRAINT ai_support_conversation_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: bookings_transactions bookings_transactions_order_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_order_code_key UNIQUE (order_code);


--
-- Name: bookings_transactions bookings_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_pkey PRIMARY KEY (id);


--
-- Name: community_post_comments community_post_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_pkey PRIMARY KEY (id);


--
-- Name: community_post_likes community_post_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_likes
    ADD CONSTRAINT community_post_likes_pkey PRIMARY KEY (id);


--
-- Name: community_posts community_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_posts
    ADD CONSTRAINT community_posts_pkey PRIMARY KEY (id);


--
-- Name: creator_upgrades creator_upgrades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.creator_upgrades
    ADD CONSTRAINT creator_upgrades_pkey PRIMARY KEY (id);


--
-- Name: missions missions_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.missions
    ADD CONSTRAINT missions_code_key UNIQUE (code);


--
-- Name: missions missions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.missions
    ADD CONSTRAINT missions_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_appointment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_appointment_id_key UNIQUE (appointment_id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: svalue_transaction_logs svalue_transaction_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.svalue_transaction_logs
    ADD CONSTRAINT svalue_transaction_logs_pkey PRIMARY KEY (id);


--
-- Name: tiktok_feed_comments tiktok_feed_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_comments
    ADD CONSTRAINT tiktok_feed_comments_pkey PRIMARY KEY (id);


--
-- Name: tiktok_feed_likes tiktok_feed_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_likes
    ADD CONSTRAINT tiktok_feed_likes_pkey PRIMARY KEY (id);


--
-- Name: tiktok_feed_saves tiktok_feed_saves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_saves
    ADD CONSTRAINT tiktok_feed_saves_pkey PRIMARY KEY (id);


--
-- Name: tiktok_feed_shares tiktok_feed_shares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_shares
    ADD CONSTRAINT tiktok_feed_shares_pkey PRIMARY KEY (id);


--
-- Name: tiktok_feeds tiktok_feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feeds
    ADD CONSTRAINT tiktok_feeds_pkey PRIMARY KEY (id);


--
-- Name: affiliate_partnerships unique_creator_partner_pair; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_partnerships
    ADD CONSTRAINT unique_creator_partner_pair UNIQUE (creator_id, partner_id);


--
-- Name: user_vouchers unique_user_voucher; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT unique_user_voucher UNIQUE (user_id, voucher_id);


--
-- Name: ai_support_conversation uq_user_partner_room; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_conversation
    ADD CONSTRAINT uq_user_partner_room UNIQUE (user_id, partner_id);


--
-- Name: user_fcm_tokens user_fcm_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_pkey PRIMARY KEY (id);


--
-- Name: user_fcm_tokens user_fcm_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_token_key UNIQUE (token);


--
-- Name: user_follows user_follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_pkey PRIMARY KEY (id);


--
-- Name: user_missions user_missions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_missions
    ADD CONSTRAINT user_missions_pkey PRIMARY KEY (id);


--
-- Name: user_missions user_missions_user_id_mission_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_missions
    ADD CONSTRAINT user_missions_user_id_mission_code_key UNIQUE (user_id, mission_code);


--
-- Name: user_svalue_wallet user_svalue_wallet_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_svalue_wallet
    ADD CONSTRAINT user_svalue_wallet_pkey PRIMARY KEY (user_id);


--
-- Name: user_vouchers user_vouchers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT user_vouchers_pkey PRIMARY KEY (id);


--
-- Name: user_wellness_logs user_wellness_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_wellness_logs
    ADD CONSTRAINT user_wellness_logs_pkey PRIMARY KEY (id);


--
-- Name: user_wellness_profiles user_wellness_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_wellness_profiles
    ADD CONSTRAINT user_wellness_profiles_pkey PRIMARY KEY (id);


--
-- Name: users users_affiliate_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_affiliate_code_key UNIQUE (affiliate_code);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: vouchers vouchers_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vouchers
    ADD CONSTRAINT vouchers_code_key UNIQUE (code);


--
-- Name: vouchers vouchers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vouchers
    ADD CONSTRAINT vouchers_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_user_id_key UNIQUE (user_id);


--
-- Name: withdrawal_requests withdrawal_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawal_requests
    ADD CONSTRAINT withdrawal_requests_pkey PRIMARY KEY (id);


--
-- Name: account_userId_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX "account_userId_idx" ON neon_auth.account USING btree ("userId");


--
-- Name: invitation_email_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX invitation_email_idx ON neon_auth.invitation USING btree (email);


--
-- Name: invitation_organizationId_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX "invitation_organizationId_idx" ON neon_auth.invitation USING btree ("organizationId");


--
-- Name: member_organizationId_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX "member_organizationId_idx" ON neon_auth.member USING btree ("organizationId");


--
-- Name: member_userId_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX "member_userId_idx" ON neon_auth.member USING btree ("userId");


--
-- Name: organization_slug_uidx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE UNIQUE INDEX organization_slug_uidx ON neon_auth.organization USING btree (slug);


--
-- Name: session_userId_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX "session_userId_idx" ON neon_auth.session USING btree ("userId");


--
-- Name: verification_identifier_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX verification_identifier_idx ON neon_auth.verification USING btree (identifier);


--
-- Name: idx_affiliate_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_affiliate_creator ON public.affiliate_partnerships USING btree (creator_id);


--
-- Name: idx_affiliate_partner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_affiliate_partner ON public.affiliate_partnerships USING btree (partner_id);


--
-- Name: idx_ai_chat_history_conv_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_chat_history_conv_time ON public.ai_support_chat_history USING btree (conversation_id, created_at DESC);


--
-- Name: idx_ai_chat_history_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_chat_history_conversation_id ON public.ai_chat_history USING btree (conversation_id);


--
-- Name: idx_ai_chat_history_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_chat_history_created_at ON public.ai_chat_history USING btree (created_at);


--
-- Name: idx_ai_conv_user_partner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_user_partner ON public.ai_support_conversation USING btree (user_id, partner_id);


--
-- Name: idx_ai_conversations_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conversations_updated_at ON public.ai_conversations USING btree (updated_at DESC);


--
-- Name: idx_ai_conversations_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conversations_user_id ON public.ai_conversations USING btree (user_id);


--
-- Name: idx_creator_upgrades_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_creator_upgrades_user_id ON public.creator_upgrades USING btree (user_id);


--
-- Name: idx_notifications_user_category_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_category_created ON public.notifications USING btree (user_id, category, created_at DESC);


--
-- Name: idx_notifications_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_unread ON public.notifications USING btree (user_id) WHERE (is_read = false);


--
-- Name: idx_reviews_partner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_partner_id ON public.reviews USING btree (partner_id);


--
-- Name: idx_reviews_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_service_id ON public.reviews USING btree (service_id);


--
-- Name: idx_user_fcm_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_fcm_tokens_user_id ON public.user_fcm_tokens USING btree (user_id);


--
-- Name: idx_user_missions_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_missions_user_id ON public.user_missions USING btree (user_id);


--
-- Name: idx_user_vouchers_locked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_vouchers_locked ON public.user_vouchers USING btree (status, locked_until);


--
-- Name: idx_user_vouchers_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_vouchers_lookup ON public.user_vouchers USING btree (user_id, status);


--
-- Name: idx_user_wellness_logs_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_wellness_logs_user_id ON public.user_wellness_logs USING btree (user_id);


--
-- Name: idx_vouchers_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vouchers_code ON public.vouchers USING btree (code);


--
-- Name: idx_vouchers_issuer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vouchers_issuer ON public.vouchers USING btree (issuer_type, issuer_id);


--
-- Name: idx_vouchers_validity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vouchers_validity ON public.vouchers USING btree (status, valid_until);


--
-- Name: uidx_creator_upgrades_pending_exclusive; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uidx_creator_upgrades_pending_exclusive ON public.creator_upgrades USING btree (user_id) WHERE ((status)::text = 'PENDING'::text);


--
-- Name: services trigger_sync_service_video; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_sync_service_video AFTER UPDATE ON public.services FOR EACH ROW EXECUTE FUNCTION public.sync_service_video_to_tiktok_feeds();


--
-- Name: user_follows trigger_update_followers_count; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_followers_count AFTER INSERT OR DELETE ON public.user_follows FOR EACH ROW EXECUTE FUNCTION public.update_followers_count();


--
-- Name: wallets trigger_update_wallet_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_wallet_timestamp BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.update_wallet_timestamp();


--
-- Name: account account_userId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.account
    ADD CONSTRAINT "account_userId_fkey" FOREIGN KEY ("userId") REFERENCES neon_auth."user"(id) ON DELETE CASCADE;


--
-- Name: invitation invitation_inviterId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.invitation
    ADD CONSTRAINT "invitation_inviterId_fkey" FOREIGN KEY ("inviterId") REFERENCES neon_auth."user"(id) ON DELETE CASCADE;


--
-- Name: invitation invitation_organizationId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.invitation
    ADD CONSTRAINT "invitation_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES neon_auth.organization(id) ON DELETE CASCADE;


--
-- Name: member member_organizationId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.member
    ADD CONSTRAINT "member_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES neon_auth.organization(id) ON DELETE CASCADE;


--
-- Name: member member_userId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.member
    ADD CONSTRAINT "member_userId_fkey" FOREIGN KEY ("userId") REFERENCES neon_auth."user"(id) ON DELETE CASCADE;


--
-- Name: session session_userId_fkey; Type: FK CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.session
    ADD CONSTRAINT "session_userId_fkey" FOREIGN KEY ("userId") REFERENCES neon_auth."user"(id) ON DELETE CASCADE;


--
-- Name: affiliate_metrics affiliate_metrics_partnership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_metrics
    ADD CONSTRAINT affiliate_metrics_partnership_id_fkey FOREIGN KEY (partnership_id) REFERENCES public.affiliate_partnerships(id) ON DELETE CASCADE;


--
-- Name: affiliate_partnerships affiliate_partnerships_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_partnerships
    ADD CONSTRAINT affiliate_partnerships_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: affiliate_partnerships affiliate_partnerships_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliate_partnerships
    ADD CONSTRAINT affiliate_partnerships_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ai_chat_history ai_chat_history_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_chat_history
    ADD CONSTRAINT ai_chat_history_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE CASCADE;


--
-- Name: ai_chat_history ai_chat_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_chat_history
    ADD CONSTRAINT ai_chat_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ai_conversations ai_conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT ai_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: appointments appointments_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings_transactions(id) ON DELETE SET NULL;


--
-- Name: appointments appointments_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: appointments appointments_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: appointments appointments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: appointments appointments_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE SET NULL;


--
-- Name: bookings_transactions bookings_transactions_affiliate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_affiliate_id_fkey FOREIGN KEY (affiliate_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: bookings_transactions bookings_transactions_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: bookings_transactions bookings_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bookings_transactions bookings_transactions_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT bookings_transactions_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE SET NULL;


--
-- Name: community_post_comments community_post_comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.community_post_comments(id) ON DELETE CASCADE;


--
-- Name: community_post_comments community_post_comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.community_posts(id) ON DELETE CASCADE;


--
-- Name: community_post_comments community_post_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: community_post_likes community_post_likes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_likes
    ADD CONSTRAINT community_post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.community_posts(id) ON DELETE CASCADE;


--
-- Name: community_post_likes community_post_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_post_likes
    ADD CONSTRAINT community_post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: community_posts community_posts_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_posts
    ADD CONSTRAINT community_posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bookings_transactions fk_bookings_voucher; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings_transactions
    ADD CONSTRAINT fk_bookings_voucher FOREIGN KEY (applied_voucher_id) REFERENCES public.vouchers(id) ON DELETE SET NULL;


--
-- Name: ai_support_conversation fk_conversation_partner; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_conversation
    ADD CONSTRAINT fk_conversation_partner FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ai_support_conversation fk_conversation_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_conversation
    ADD CONSTRAINT fk_conversation_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: creator_upgrades fk_creator_upgrades_moderator; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.creator_upgrades
    ADD CONSTRAINT fk_creator_upgrades_moderator FOREIGN KEY (moderated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: creator_upgrades fk_creator_upgrades_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.creator_upgrades
    ADD CONSTRAINT fk_creator_upgrades_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ai_support_chat_history fk_history_conversation; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_support_chat_history
    ADD CONSTRAINT fk_history_conversation FOREIGN KEY (conversation_id) REFERENCES public.ai_support_conversation(id) ON DELETE CASCADE;


--
-- Name: user_vouchers fk_user_vouchers_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT fk_user_vouchers_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_vouchers fk_user_vouchers_voucher; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT fk_user_vouchers_voucher FOREIGN KEY (voucher_id) REFERENCES public.vouchers(id) ON DELETE CASCADE;


--
-- Name: vouchers fk_vouchers_issuer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vouchers
    ADD CONSTRAINT fk_vouchers_issuer FOREIGN KEY (issuer_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_appointment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES public.appointments(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: services services_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: services services_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_comments tiktok_feed_comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_comments
    ADD CONSTRAINT tiktok_feed_comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.tiktok_feed_comments(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_comments tiktok_feed_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_comments
    ADD CONSTRAINT tiktok_feed_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_comments tiktok_feed_comments_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_comments
    ADD CONSTRAINT tiktok_feed_comments_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_likes tiktok_feed_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_likes
    ADD CONSTRAINT tiktok_feed_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_likes tiktok_feed_likes_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_likes
    ADD CONSTRAINT tiktok_feed_likes_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_saves tiktok_feed_saves_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_saves
    ADD CONSTRAINT tiktok_feed_saves_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_saves tiktok_feed_saves_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_saves
    ADD CONSTRAINT tiktok_feed_saves_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_shares tiktok_feed_shares_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_shares
    ADD CONSTRAINT tiktok_feed_shares_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feed_shares tiktok_feed_shares_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feed_shares
    ADD CONSTRAINT tiktok_feed_shares_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.tiktok_feeds(id) ON DELETE CASCADE;


--
-- Name: tiktok_feeds tiktok_feeds_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feeds
    ADD CONSTRAINT tiktok_feeds_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tiktok_feeds tiktok_feeds_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tiktok_feeds
    ADD CONSTRAINT tiktok_feeds_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: user_follows user_follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_follows user_follows_following_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_follows
    ADD CONSTRAINT user_follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_missions user_missions_mission_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_missions
    ADD CONSTRAINT user_missions_mission_code_fkey FOREIGN KEY (mission_code) REFERENCES public.missions(code) ON DELETE CASCADE;


--
-- Name: user_vouchers user_vouchers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT user_vouchers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_vouchers user_vouchers_voucher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_vouchers
    ADD CONSTRAINT user_vouchers_voucher_id_fkey FOREIGN KEY (voucher_id) REFERENCES public.vouchers(id) ON DELETE CASCADE;


--
-- Name: user_wellness_logs user_wellness_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_wellness_logs
    ADD CONSTRAINT user_wellness_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_wellness_profiles user_wellness_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_wellness_profiles
    ADD CONSTRAINT user_wellness_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: vouchers vouchers_issuer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vouchers
    ADD CONSTRAINT vouchers_issuer_id_fkey FOREIGN KEY (issuer_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: wallets wallets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: withdrawal_requests withdrawal_requests_processed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawal_requests
    ADD CONSTRAINT withdrawal_requests_processed_by_fkey FOREIGN KEY (processed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: withdrawal_requests withdrawal_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawal_requests
    ADD CONSTRAINT withdrawal_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict GXMLBytf23mtjvtlVgrnpPwgXuO9lDMJsAHaBXes79njQj04cBaUh9Ud90LGGUZ

