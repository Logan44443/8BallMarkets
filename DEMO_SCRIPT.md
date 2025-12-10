# 8Ball Markets - 10 Minute Demo Script

## Pre-Demo Setup (Before Recording)
- [ ] Ensure seed data is loaded (100 users with bet history)
- [ ] Have test accounts ready:
  - `alainfornes` (Admin) - Password: `Password`
  - `carlospenzini` (Regular user) - Password: `Password`
  - `lukashorvat` (Regular user) - Password: `Password`
- [ ] Open browser in incognito/private mode
- [ ] Have a second browser window ready for multi-user testing
- [ ] Clear any existing localStorage data

---

## Demo Flow (10 Minutes)

### 1. Introduction & Login (0:00 - 0:45)
**Time: 45 seconds**

- [ ] **Show landing page** - Mention the animated money emoji background
- [ ] **Navigate to login page**
- [ ] **Login as `alainfornes`** (admin account)
- [ ] **Briefly mention**: "This is a peer-to-peer betting platform where users can create and accept bets on any event"

**Key Points:**
- Clean, modern UI with dynamic background
- Simple authentication system

---

### 2. Dashboard Overview (0:45 - 1:30)
**Time: 45 seconds**

- [ ] **Show dashboard** - Highlight:
  - Wallet balance display (top right)
  - Friends list section
  - Support tickets section
  - Navigation menu
- [ ] **Quick tour of navigation**: Dashboard, Create Bet, Marketplace, My Bets, Profile, Leaderboard
- [ ] **Mention**: "Users start with a wallet balance and can bet with other users"

**Key Points:**
- Central hub for all user activities
- Real-time balance display
- Social features (friends)

---

### 3. Creating a Bet (1:30 - 2:30)
**Time: 60 seconds**

- [ ] **Navigate to "Create Bet"**
- [ ] **Fill out bet form**:
  - Event description: "Will it rain tomorrow?"
  - Stake: $50
  - Select an arbiter (optional)
- [ ] **Submit bet** - Show balance decrease
- [ ] **Explain**: "When you create a bet, funds are held in escrow until someone accepts it"
- [ ] **Navigate to "My Bets"** - Show the pending bet
- [ ] **Mention**: "You can cancel pending bets if no one has accepted yet"

**Key Points:**
- Funds are held immediately upon creation
- Bet stays in PENDING until accepted
- Can cancel before acceptance

---

### 4. Accepting a Bet (2:30 - 3:30)
**Time: 60 seconds**

- [ ] **Switch to second browser** (or logout/login as different user)
- [ ] **Login as `carlospenzini`**
- [ ] **Navigate to "Marketplace"** - Show available bets
- [ ] **Click on a bet** - Show bet details
- [ ] **Accept the bet** - Show balance decrease
- [ ] **Explain**: "When you accept, your stake is also held. The bet becomes ACTIVE"
- [ ] **Navigate to "My Bets"** - Show the active bet
- [ ] **Switch back to first account** - Show the bet is now ACTIVE

**Key Points:**
- Marketplace shows all available bets
- Both parties' funds are held when bet is accepted
- Bet transitions from PENDING → ACTIVE

---

### 5. Resolving a Bet (3:30 - 4:30)
**Time: 60 seconds**

- [ ] **Login as arbiter** (or use admin account)
- [ ] **Navigate to "Arbiter Dashboard"**
- [ ] **Show list of active bets** that need resolution
- [ ] **Select a bet** - Show bet details
- [ ] **Resolve bet** - Choose winner (PROPOSER_WIN or ACCEPTOR_WIN)
- [ ] **Add resolution notes** (optional)
- [ ] **Submit resolution**
- [ ] **Switch back to proposer account** - Show balance updated (winner gets both stakes)
- [ ] **Navigate to "My Bets"** - Show resolved bet in "Past Bets" section

**Key Points:**
- Arbiters can resolve active bets
- Winners receive both stakes
- Bet transitions from ACTIVE → RESOLVED

---

### 6. Profile & Leaderboard (4:30 - 5:30)
**Time: 60 seconds**

- [ ] **Navigate to "Profile"** (own profile)
- [ ] **Show profile features**:
  - Win/Loss record at top
  - Current bets section
  - Past bets section (with outcomes)
- [ ] **Click on a friend's name** - Show other user's profile
- [ ] **Navigate to "Leaderboard"**
- [ ] **Show leaderboard features**:
  - Ranked by total profit
  - Shows wins, losses, win rate, total wagered
  - Sortable columns
- [ ] **Mention**: "Leaderboard updates in real-time as bets are resolved"

**Key Points:**
- Personal betting history
- View other users' profiles
- Competitive leaderboard system

---

### 7. Friends System (5:30 - 6:15)
**Time: 45 seconds**

- [ ] **Navigate back to Dashboard**
- [ ] **Show Friends section**
- [ ] **Search for a user** (e.g., "carlos")
- [ ] **Send friend request**
- [ ] **Switch to second account** - Show incoming friend request
- [ ] **Accept friend request**
- [ ] **Switch back** - Show friend now in friends list
- [ ] **Mention**: "Friends can see each other's activity and bet history"

**Key Points:**
- Search and add friends
- Friend request system
- Friends list management

---

### 8. Support Tickets (6:15 - 7:00)
**Time: 45 seconds**

- [ ] **On Dashboard, scroll to Support Tickets**
- [ ] **Click "Create Support Ticket"**
- [ ] **Fill out ticket**:
  - Subject: "Question about bet resolution"
  - Message: "How do I dispute a bet?"
- [ ] **Submit ticket**
- [ ] **Show ticket in "My Tickets" list**
- [ ] **Click on ticket** - Show ticket details
- [ ] **Mention**: "Admins can respond to tickets"

**Key Points:**
- User support system
- Ticket creation and tracking
- Admin response capability

---

### 9. Admin Features (7:00 - 8:00)
**Time: 60 seconds**

- [ ] **Login as admin** (`alainfornes`)
- [ ] **Navigate to "Admin Dashboard"**
- [ ] **Show admin features**:
  - All bets (can resolve any bet)
  - All support tickets
  - User management capabilities
- [ ] **Resolve a support ticket**:
  - Click on a ticket
  - Add admin response
  - Mark as resolved
- [ ] **Resolve a disputed bet** (if any exist)
- [ ] **Mention**: "Admins have elevated privileges to manage the platform"

**Key Points:**
- Admin oversight capabilities
- Can resolve any bet
- Support ticket management

---

### 10. Advanced Features & Wrap-up (8:00 - 10:00)
**Time: 120 seconds**

- [ ] **Show "My Bets" page** - Demonstrate:
  - Filtering by status (Pending, Active, Resolved)
  - Direct bets vs Marketplace bets
  - Bet cancellation
- [ ] **Show dispute feature**:
  - On an active bet, show "Dispute" button
  - Explain: "If you disagree with a resolution, you can dispute"
- [ ] **Navigate to Marketplace** - Show:
  - Multiple available bets
  - Filtering options
  - Bet details modal
- [ ] **Quick recap of key features**:
  - ✅ Peer-to-peer betting
  - ✅ Escrow system (funds held securely)
  - ✅ Arbiter system for fair resolution
  - ✅ Social features (friends)
  - ✅ Support system
  - ✅ Leaderboard competition
  - ✅ Admin oversight
- [ ] **Show animated background** - Mention the polished UI/UX
- [ ] **Final thoughts**: "This is a complete MVP with all core betting functionality, social features, and administrative tools"

**Key Points:**
- Comprehensive feature set
- Production-ready UI
- Scalable architecture

---

## Post-Demo Checklist
- [ ] Verify all features worked correctly
- [ ] Check console for any errors
- [ ] Ensure balance calculations are accurate
- [ ] Verify leaderboard shows correct data

---

## Tips for Recording
1. **Speak clearly** - Explain what you're doing as you do it
2. **Show, don't tell** - Let the UI speak for itself
3. **Highlight key moments**:
   - Balance changes
   - Status transitions (PENDING → ACTIVE → RESOLVED)
   - Real-time updates
4. **Use keyboard shortcuts** - Makes demo smoother
5. **Have backup plans** - If something doesn't work, have alternative scenarios ready
6. **Keep it concise** - 10 minutes goes fast, prioritize core features

---

## Feature Summary for Quick Reference

### Core Betting Features
- ✅ Create bets (marketplace & direct)
- ✅ Accept bets
- ✅ Cancel pending bets
- ✅ Resolve bets (arbiter/admin)
- ✅ Dispute bets
- ✅ View bet history

### Financial Features
- ✅ Wallet balance system
- ✅ Escrow (funds held during active bets)
- ✅ Automatic payouts on resolution
- ✅ Transaction history (via ledger)

### Social Features
- ✅ Friend requests
- ✅ Friends list
- ✅ User profiles
- ✅ View other users' bet history

### Administrative Features
- ✅ Admin dashboard
- ✅ Resolve any bet
- ✅ Support ticket management
- ✅ User oversight

### UI/UX Features
- ✅ Animated money emoji background
- ✅ Responsive design
- ✅ Real-time balance updates
- ✅ Clean, modern interface
- ✅ Leaderboard with sorting

---

## Potential Demo Scenarios

### Scenario 1: Complete Bet Lifecycle
1. User A creates bet
2. User B accepts bet
3. Arbiter resolves bet
4. Show winner's balance increase

### Scenario 2: Social Interaction
1. Search for friend
2. Send friend request
3. Accept request
4. View friend's profile

### Scenario 3: Support Flow
1. User creates support ticket
2. Admin views ticket
3. Admin responds
4. User sees response

### Scenario 4: Leaderboard Competition
1. Show current leaderboard
2. Resolve a bet
3. Refresh leaderboard
4. Show updated rankings

---

**Total Estimated Time: ~10 minutes**
**Buffer Time: 1-2 minutes for transitions and explanations**

