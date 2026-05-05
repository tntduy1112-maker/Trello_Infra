# TaskFlow - Delivery Note & User Guide

> Version 1.0 | Last Updated: May 2026

## Overview

TaskFlow is a collaborative project management application inspired by Trello. It enables teams to organize work using boards, lists, and cards with real-time collaboration features.

---

## Implemented Features

### 1. Authentication

| Feature | Description |
|---------|-------------|
| **Login** | Sign in with email and password |
| **JWT Authentication** | Secure token-based authentication with auto-refresh |
| **Logout** | Sign out and clear session |
| **Invitation-Only Registration** | New users can only join via workspace/board invitations |

### 2. Workspaces (Organizations)

| Feature | Description |
|---------|-------------|
| **Create Workspace** | Create a new workspace to organize your boards |
| **Workspace Settings** | Update workspace name and description |
| **Member Management** | Invite and manage workspace members |

### 3. Boards

| Feature | Description |
|---------|-------------|
| **Create Board** | Create a new board within a workspace |
| **Board Background** | Customize board with background colors |
| **Board Settings** | Update board title and settings |
| **Board Visibility** | Control who can see and access the board |

### 4. Board Members & Roles

| Role | Permissions |
|------|-------------|
| **Owner** | Full control, can delete board, manage all members |
| **Admin** | Can manage members, create/edit all content |
| **Member** | Can create and edit cards, lists, comments |
| **Viewer** | Read-only access to board content |

**Invite Members**: Send email invitations to add new members to a board.

### 5. Lists

| Feature | Description |
|---------|-------------|
| **Create List** | Add new lists to organize cards |
| **Rename List** | Click on list title to edit |
| **Move List** | Drag and drop to reorder lists |
| **Archive List** | Remove list from board (can be restored) |

### 6. Cards

| Feature | Description |
|---------|-------------|
| **Create Card** | Add new cards to any list |
| **Edit Card** | Click card to open detail modal |
| **Move Card** | Drag and drop between lists or within a list |
| **Card Title** | Edit card title inline |
| **Description** | Add detailed description to cards |
| **Due Date** | Set deadlines with date picker |
| **Priority** | Set priority level (None, Low, Medium, High) |
| **Assignee** | Assign card to a board member |
| **Mark Complete** | Mark cards as completed |
| **Archive Card** | Remove card from board |

### 7. Labels

| Feature | Description |
|---------|-------------|
| **Create Labels** | Create colored labels for categorization |
| **Assign Labels** | Add multiple labels to a card |
| **Label Colors** | Choose from preset colors or custom colors |
| **Remove Labels** | Unassign labels from cards |

### 8. Comments

| Feature | Description |
|---------|-------------|
| **Add Comment** | Write comments on cards |
| **@Mentions** | Type `@` to mention board members |
| **Edit Comment** | Edit your own comments |
| **Delete Comment** | Remove your own comments |
| **Reply** | Reply to existing comments (threaded) |
| **Newest First** | Comments ordered with latest at top |

### 9. Checklists

| Feature | Description |
|---------|-------------|
| **Create Checklist** | Add checklists to cards |
| **Add Items** | Add items to checklists |
| **Check/Uncheck** | Mark items as complete |
| **Progress Bar** | Visual progress indicator |
| **Delete Items** | Remove checklist items |
| **Delete Checklist** | Remove entire checklist |

### 10. Attachments

| Feature | Description |
|---------|-------------|
| **Upload Files** | Attach files to cards |
| **File Preview** | Preview images and documents |
| **Download** | Download attached files |
| **Delete** | Remove attachments |

### 11. Notifications

| Feature | Description |
|---------|-------------|
| **Real-time Updates** | Instant notifications via Server-Sent Events |
| **Notification Bell** | Badge shows unread count |
| **Notification Types** | Mentions, comments, assignments, due dates |
| **Mark as Read** | Mark individual or all notifications as read |
| **Click to Navigate** | Click notification to go directly to the card |

### 12. Activity Log

| Feature | Description |
|---------|-------------|
| **Activity Feed** | View all actions on a card |
| **Board Activity** | See recent activity across the board |
| **Action History** | Track who did what and when |

---

## User Guide

### Getting Started

1. **Join via Invitation**
   - Receive an invitation email from your team
   - Click the invitation link to set up your account
   - Enter your details and create a password

2. **Create Your First Workspace**
   - After login, click "Create Workspace"
   - Enter a name for your workspace
   - This is where all your boards will live

3. **Create a Board**
   - Inside your workspace, click "Create Board"
   - Give your board a name
   - Choose a background color
   - Click "Create"

### Working with Lists and Cards

1. **Add a List**
   - Click "+ Add another list" on the right side of your board
   - Enter a list name (e.g., "To Do", "In Progress", "Done")
   - Press Enter or click "Add List"

2. **Add a Card**
   - Click "+ Add a card" at the bottom of any list
   - Enter a card title
   - Press Enter or click "Add Card"

3. **Edit a Card**
   - Click on any card to open the detail modal
   - Here you can:
     - Edit the title and description
     - Add labels, due dates, and assignees
     - Create checklists
     - Add comments
     - Attach files

4. **Drag and Drop**
   - Drag cards between lists to change their status
   - Drag lists to reorder them on the board
   - Changes are saved automatically

### Collaborating with Your Team

1. **Invite Members**
   - Click the "Invite" button on your board
   - Enter the email address of the person you want to invite
   - Choose their role (Admin, Member, or Viewer)
   - They will receive an email invitation

2. **Mention Team Members**
   - In any comment, type `@` followed by a name
   - Select the person from the dropdown
   - They will receive a notification

3. **View Notifications**
   - Click the bell icon in the header
   - See all your notifications
   - Click on a notification to go to that card
   - Mark notifications as read

### Tips & Tricks

| Tip | Description |
|-----|-------------|
| **Quick Add** | Press Enter after typing to quickly add cards |
| **Keyboard Navigation** | Use arrow keys in mention dropdown |
| **Escape to Close** | Press Escape to close modals and dropdowns |
| **Click Outside** | Click outside a modal to close it |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Confirm/Submit |
| `Escape` | Cancel/Close |
| `@` | Open mention picker (in comments) |
| `Arrow Keys` | Navigate dropdowns |

---

## Troubleshooting

### Common Issues

**Can't see my boards?**
- Make sure you're in the correct workspace
- Check if you have access to the board

**Not receiving notifications?**
- Check your browser allows notifications
- Refresh the page to reconnect

**Drag and drop not working?**
- Make sure you're clicking and holding on the card/list
- Try refreshing the page

**Can't edit a card?**
- Check your role - Viewers have read-only access
- Ask a board admin to update your permissions

---

## Technical Specifications

### Browser Support
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

### API Endpoints

Base URL: `/api/v1`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth/login` | POST | Login |
| `/invitations/accept` | POST | Accept invitation and create account |
| `/workspaces` | GET/POST | List/Create workspaces |
| `/boards` | GET/POST | List/Create boards |
| `/boards/:id` | GET/PATCH/DELETE | Board operations |
| `/lists` | POST | Create list |
| `/lists/:id` | PATCH/DELETE | List operations |
| `/cards` | POST | Create card |
| `/cards/:id` | GET/PATCH/DELETE | Card operations |
| `/notifications` | GET | Get notifications |
| `/notifications/stream` | GET | SSE stream |

---

## Support

If you encounter any issues or have questions:

1. Check this help documentation
2. Contact your workspace administrator
3. Report bugs at: [GitHub Issues](https://github.com/tntduy1112-maker/Trello_Backend_Golang_1st/issues)

---

## Release History

### Version 1.0 (May 2026)
- Initial release
- Core features: Boards, Lists, Cards
- Collaboration: Members, Comments, @Mentions
- Organization: Labels, Checklists, Attachments
- Real-time: Notifications via SSE
- Activity tracking and audit log
- Invitation-only user registration (no public signup)
