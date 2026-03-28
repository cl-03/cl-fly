create table if not exists visitors (
  id bigserial primary key,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists agents (
  id bigserial primary key,
  username text not null unique,
  role text not null,
  password_hash text not null default '',
  must_change_password boolean not null default false,
  created_at timestamptz not null default now()
);

alter table agents add column if not exists password_hash text not null default '';
alter table agents add column if not exists must_change_password boolean not null default false;

create table if not exists sessions (
  id bigserial primary key,
  visitor_id bigint not null references visitors(id),
  assignee_agent_id bigint references agents(id),
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists messages (
  id bigserial primary key,
  session_id bigint not null references sessions(id),
  sender_role text not null,
  content text not null,
  client_msg_id text,
  created_at timestamptz not null default now(),
  unique (session_id, client_msg_id)
);

create table if not exists audit_logs (
  id bigserial primary key,
  actor text not null,
  action text not null,
  target_type text not null,
  target_id text,
  details text,
  created_at timestamptz not null default now()
);

create index if not exists idx_sessions_status on sessions(status);
create index if not exists idx_messages_session_created on messages(session_id, created_at desc);
create index if not exists idx_audit_logs_created on audit_logs(created_at desc);
