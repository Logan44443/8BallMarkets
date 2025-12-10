Team Name: 8Ball Markets

Team Members: Logan Azizzadeh, Lukas Horvat, Dylan Cohen, Carlos Penzini, Alain Fornes, Leonardo Lanfranchi

Github link: https://github.com/Logan44443/8BallMarkets 

Final Project Video Link:
https://drive.google.com/file/d/14ykCZBhYey18AX2grfYdl2-oK8yqqj1s/view?usp=sharing


Progress: Since Milestone 4, we focused on security, admin features, and creating a complete 
peer to peer betting ecosystem. We implemented RLS across all database tables with proper 
authentication context management using PostgreSQL session variables. The app now features a 
comprehensive admin system for managing support tickets and resolving disputes, a third party 
arbiter system for neutral bet verification, and public profile pages with accurate win/loss 
calculations. We added a leaderboard with deterministic calculations ensuring consistent rankings, 
enhanced the UI with a British racing green theme and animated money emoji background, and created 
a robust test dataset with 100+ users and 400+ resolved bets. We fixed critical bugs including 
double deduction issues, balance synchronization, win/loss calculation accuracy, and leaderboard 
consistency. The financial system uses a double-entry ledger with automatic wallet balance sync, 
and all bet operations (create, accept, resolve) are handled atomically through SECURITY DEFINER 
stored procedures. Environment variables secure API keys, and users can sign up directly from the 
login page with a $1000 starting balance.

Logan: User guru - Authentication system, signup flow with starting balance, user profile pages with betting history, and RLS policy implementation

Dylan: Transactions guru - Double-entry ledger system, wallet balance synchronization triggers, leaderboard with deterministic calculations, and financial transaction integrity

Carlos: Direct bets guru - Bet resolution system, arbiter dashboard, dispute handling, bet status machine enforcement, and authorization checks for bet operations

Lukas: Comments and support guru - Admin dashboard with bet and ticket management, support ticket system with chat interface, and admin privilege enforcement

Leonardo: Social guru - Friends system with request/accept flow, friends list display, user search functionality, and social interaction features

Alain: Order book guru - Marketplace infrastructure, seed data generator for 100+ users, UI design with animated background, bug fixes for balance sync and leaderboard consistency, and RPC functions for data access




