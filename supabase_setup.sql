create extension if not exists pgcrypto;

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  inquiry_code text not null unique,
  lead_type text not null check (lead_type in ('group_order','class','writer')),
  status text not null default '신규 견적',
  contact_name text not null check (char_length(contact_name) between 1 and 60),
  phone text not null check (char_length(phone) between 9 and 20),
  company text check (company is null or char_length(company) <= 100),
  email text check (email is null or char_length(email) <= 160),
  event_date date,
  requested_time text check (requested_time is null or char_length(requested_time) <= 40),
  fulfillment_method text check (fulfillment_method is null or fulfillment_method in ('delivery','pickup')),
  address text check (address is null or char_length(address) <= 300),
  package_type text check (package_type is null or package_type in ('A','B','C','custom')),
  quantity integer,
  menu1 text check (menu1 is null or char_length(menu1) <= 80),
  menu1_qty integer,
  menu2 text check (menu2 is null or char_length(menu2) <= 80),
  menu2_qty integer,
  drink_change text check (drink_change is null or char_length(drink_change) <= 200),
  excluded_ingredients text check (excluded_ingredients is null or char_length(excluded_ingredients) <= 300),
  receipt_type text check (receipt_type is null or receipt_type in ('card','cash','none')),
  estimated_subtotal integer check (estimated_subtotal is null or estimated_subtotal >= 0),
  notes text check (notes is null or char_length(notes) <= 1000),
  privacy_consent boolean not null default false,
  terms_consent boolean not null default false,
  source text check (source is null or char_length(source) <= 80),
  utm_source text check (utm_source is null or char_length(utm_source) <= 80),
  utm_medium text check (utm_medium is null or char_length(utm_medium) <= 80),
  utm_campaign text check (utm_campaign is null or char_length(utm_campaign) <= 120),
  next_action_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_order_rules check (
    lead_type <> 'group_order' or (
      event_date is not null
      and quantity between 20 and 150
      and package_type is not null
      and fulfillment_method is not null
      and menu1 is not null
      and menu1_qty >= 0
      and menu1_qty % 2 = 0
      and coalesce(menu2_qty,0) >= 0
      and coalesce(menu2_qty,0) % 2 = 0
      and menu1_qty + coalesce(menu2_qty,0) = quantity
      and (fulfillment_method <> 'delivery' or address is not null)
    )
  )
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists inquiries_set_updated_at on public.inquiries;
create trigger inquiries_set_updated_at
before update on public.inquiries
for each row execute function public.set_updated_at();

alter table public.inquiries enable row level security;

drop policy if exists "public_group_order_intake" on public.inquiries;
create policy "public_group_order_intake"
on public.inquiries
for insert
to anon
with check (
  lead_type = 'group_order'
  and status = '신규 견적'
  and privacy_consent = true
  and terms_consent = true
  and event_date >= current_date + 15
  and extract(dow from event_date) <> 3
  and quantity between 20 and 150
);

drop policy if exists "owner_manage_inquiries" on public.inquiries;
create policy "owner_manage_inquiries"
on public.inquiries
for all
to authenticated
using ((auth.jwt() ->> 'email') in ('a01064866933@gmail.com','19799947js@daum.net'))
with check ((auth.jwt() ->> 'email') in ('a01064866933@gmail.com','19799947js@daum.net'));

grant insert on table public.inquiries to anon;
grant select, insert, update, delete on table public.inquiries to authenticated;
revoke select, update, delete on table public.inquiries from anon;

create table if not exists public.reply_templates (
  id uuid primary key default gen_random_uuid(),
  lead_type text not null check (lead_type in ('group_order','class','writer')),
  stage text not null,
  title text not null,
  body text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lead_type, title)
);

alter table public.reply_templates enable row level security;
drop policy if exists "owner_manage_templates" on public.reply_templates;
create policy "owner_manage_templates"
on public.reply_templates
for all
to authenticated
using ((auth.jwt() ->> 'email') in ('a01064866933@gmail.com','19799947js@daum.net'))
with check ((auth.jwt() ->> 'email') in ('a01064866933@gmail.com','19799947js@daum.net'));
grant select, insert, update, delete on table public.reply_templates to authenticated;
revoke all on table public.reply_templates from anon;

insert into public.reply_templates (lead_type, stage, title, body, sort_order) values
('group_order','신규 견적','첫 견적 접수','안녕하세요, 더상큼하루입니다. 보내주신 단체주문 내용을 확인했습니다. 제작 가능 여부와 퀵 비용을 확인해 3시간 이내 안내드리겠습니다.',10),
('group_order','견적 발송','견적 안내','안녕하세요. 요청하신 일정에 제작 가능합니다. 상품 금액은 {{estimated_subtotal}}원이며 퀵 비용은 배송지 확인 후 별도 안내드립니다. 구성과 수량을 최종 확인해 주세요.',20),
('group_order','결제 대기','결제 전 확인','최종 구성 확인 후 전액 결제가 완료되면 재료를 발주합니다. 재료 발주 후에는 취소와 수량 변경이 어렵습니다. 내용을 확인하신 뒤 결제를 진행해 주세요.',30),
('group_order','결제 완료','결제 완료','결제가 확인되어 주문이 확정되었습니다. 요청하신 일정에 맞춰 정성껏 준비하겠습니다.',40),
('class','신규 신청','클래스 첫 안내','안녕하세요, 더상큼하루 샌드위치 창업 클래스입니다. 수업은 1인 98만원이며 재료비와 부가세가 포함됩니다. 월요일 오전 10시 정규 수업과 협의 가능한 주말 수업이 있습니다.',10),
('class','일정 확인','주말 일정 확인','주말 수업은 매장 일정 확인 후 확정됩니다. 원하시는 날짜를 2~3개 보내주시면 가능한 일정을 안내드리겠습니다.',20),
('class','결제 완료','클래스 확정','결제가 확인되어 클래스 일정이 확정되었습니다. 수업은 총 5시간 진행되며 자세한 준비사항은 수업 전에 다시 안내드리겠습니다.',30)
on conflict (lead_type, title) do update set body = excluded.body, stage = excluded.stage, sort_order = excluded.sort_order;


drop policy if exists "public_class_intake" on public.inquiries;
create policy "public_class_intake"
on public.inquiries
for insert
to anon
with check (
  lead_type = 'class'
  and status = '신규 신청'
  and privacy_consent = true
  and terms_consent = true
  and event_date > current_date
  and estimated_subtotal = 980000
);


drop policy if exists "public_writer_intake" on public.inquiries;
create policy "public_writer_intake"
on public.inquiries
for insert
to anon
with check (
  lead_type = 'writer'
  and status = '신규 문의'
  and privacy_consent = true
  and terms_consent = true
  and char_length(trim(contact_name)) between 1 and 60
  and char_length(trim(phone)) between 8 and 20
  and email is not null
);

insert into public.reply_templates (lead_type, stage, title, body, sort_order) values
('writer','신규 문의','제안 접수','안녕하세요, 박지성 작가입니다. 보내주신 제안을 잘 받았습니다. 일정과 내용을 확인한 뒤 답변드리겠습니다.',10),
('writer','협의 중','협업 확인','제안해 주신 내용으로 진행 가능합니다. 세부 일정과 장소, 준비사항을 함께 조율하겠습니다.',20)
on conflict (lead_type, title) do update set body = excluded.body, stage = excluded.stage, sort_order = excluded.sort_order;
