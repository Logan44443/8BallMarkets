# 8Ball Markets Setup Instructions

## Step 1: Create Test Users in Database

1. Open Supabase Studio: http://127.0.0.1:54323
2. Click "SQL Editor" in the left sidebar
3. Copy/paste the contents of `TEST_USERS.sql` and run

This creates two test users:
- Username: `alainfornes`, Password: `Password`, Balance: $10,000
- Username: `carlospenzini`, Password: `Password`, Balance: $10,000

## Step 2: Run the Frontend

```bash
cd app
npm run dev
```

The app will be available at: http://localhost:3000

## Step 3: Login

1. Go to http://localhost:3000 (will redirect to login)
2. Enter username: `alainfornes` or `carlospenzini`
3. Enter password: `Password`
4. Click "Login"

You'll be redirected to the dashboard showing your wallet balance.

**Note:** Use `carlospenzini` to test Direct Bet search functionality!

