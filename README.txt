Team Name: 8Ball Markets

Team Members: Logan Azizzadeh, Lukas Horvat, Dylan Cohen, Carlos Penzini, Alain Fornes, Leonardo Lanfranchi

Github link: https://github.com/Logan44443/8BallMarkets 

Progress: Since the last milestone, we set up a local Supabase PostgreSQL database and 
consolidated all our SQL schemas into a unified structure. We built a Next.js frontend with 
ShadCN UI components and connected it to the backend. Each guru implemented their core feature
with at least one API endpoint and corresponding frontend element. We simplified the database
schema to focus on MVP features for our demo, removing unnecessary complexity like two-factor
authentication and advanced statistics. The app now supports user login, wallet balances,
creating and accepting bets with escrow, bet-specific chat, friend requests, and support tickets.

Logan: User guru - authentication system and user management
  (Implementation: app/app/login/page.tsx for user authentication)
Dylan: Transactions guru - wallet balance and escrow logic  
  (Implementation: Wallet balance in app/app/dashboard/page.tsx, escrow in create/accept bet flows)
Carlos: Direct bets guru - bet creation and marketplace
  (Implementation: app/app/bets/create/page.tsx and app/app/bets/marketplace/page.tsx)
Lukas: Comments and support guru - chat interface and support tickets
  (Implementation: Chat dialog in app/app/bets/my-bets/page.tsx, support ticket dialog in app/app/dashboard/page.tsx)
Leonardo: Social guru - friend requests and friend list management
  (Implementation: Friends List card in app/app/dashboard/page.tsx with search, requests, and friend list)
Alain: Order book guru - Tech stack setup, Marketplace
  (Implementation: Supabase setup in supabase/migrations/, frontend structure in app/, marketplace in app/app/bets/marketplace/page.tsx)

