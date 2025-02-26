# TriviaAdvisor Frontend Design Specification

## Overview

TriviaAdvisor is a platform that helps users find and track pub quiz nights and trivia events in their area. Think of it as a "Yelp for pub quizzes" - helping trivia enthusiasts discover new venues and keep track of their favorite quiz nights.

## Core Features

- 🎯 Find trivia nights near you
- 📅 Track recurring events by venue
- 🌐 Aggregates data from multiple trivia providers
- 🗺️ Map integration for easy venue discovery
- 📱 Mobile-friendly interface

## Page Designs

### 1. Home/Index Page

The main landing page that introduces users to TriviaAdvisor.

#### Elements:

1. **Hero Section**
   - Catchy headline: "Find the Best Pub Quizzes Near You"
   - Search bar with location input and "Find Trivia" button
   - Background image of a lively pub quiz

2. **How It Works Section**
   - 3-4 steps with icons: Find → Attend → Rate → Repeat
   - Simple illustrations for each step

3. **Featured Trivia Nights**
   - Cards showing popular venues with:
     - Venue image
     - Venue name
     - Day/time of quiz
     - Entry fee
     - Rating (stars)
     - Brief description (2-3 lines)

4. **Map Component**
   - Interactive map with pins for nearby trivia venues
   - Sidebar with filterable list view

5. **Popular Cities Section**
   - Grid of city cards with:
     - City image
     - City name
     - Number of venues/events

6. **Upcoming Events Feed**
   - Timeline view of events happening soon
   - Day/date headers
   - Event cards with time, venue, and quick-action buttons

7. **Newsletter Signup**
   - Email input
   - "Get weekly trivia updates" pitch

8. **Footer**
   - Navigation links
   - Social media icons
   - Copyright/legal

### 2. Country Page

Overview of trivia events in a specific country.

#### Elements:

1. **Country Header**
   - Country name and flag
   - Total venues/events count
   - Featured image representing country

2. **Popular Cities**
   - Grid/list of cities with:
     - City name
     - Venue count
     - Representative image
     - "View City" button

3. **Upcoming Events**
   - Filterable timeline of events
   - Calendar view toggle
   - List view with venue cards

4. **Top Rated Venues**
   - Carousel of highest-rated venues in the country
   - Rating badges
   - Quick view of next quiz day/time

5. **Map View**
   - Country map with city/venue clusters
   - Zoom controls

### 3. City Page

Trivia events in a specific city.

#### Elements:

1. **City Header**
   - City name and image
   - Quick stats (# of venues, average rating)
   - Weather widget (optional for "tonight's trivia weather")

2. **This Week's Events**
   - Day-by-day timeline of events
   - Calendar view option
   - Filter by neighborhood/district

3. **Venue Listings**
   - Sortable by:
     - Distance
     - Rating
     - Entry fee
     - Day of week
   - List/Grid view toggle
   - Each venue card shows:
     - Venue image
     - Name
     - Address
     - Quiz day and time
     - Price indicator (£, ££, £££)
     - Brief description
     - "Save" button

4. **Local Map**
   - Interactive map centered on city
   - Pins for all venues
   - Popup info on pin click
   - Current location marker

5. **Neighborhood Filter**
   - Quick-select buttons for city districts
   - Count indicator of venues per area

### 4. Venue Detail Page

Information about a specific venue and its events.

#### Elements:

1. **Venue Header**
   - Hero image of venue
   - Venue name and rating
   - Address with map pin icon
   - Save/favorite button
   - Share button

2. **Key Details Panel**
   - Quiz day and time (with next occurrence date)
   - Entry fee
   - Format (team size, rounds, etc.)
   - Prizes information
   - Host/provider name

3. **Description Area**
   - Full venue description
   - Special rules or requirements
   - Theme information if applicable

4. **Media Gallery**
   - Photos of venue/events
   - User-submitted photos section

5. **Practical Information**
   - Contact details (phone, website)
   - Opening hours
   - Amenities (food, parking, accessibility)
   - Public transport options

6. **Map Section**
   - Embedded map
   - Directions button
   - Nearby venues carousel

7. **Reviews Section**
   - Overall rating display
   - User reviews with:
     - Rating
     - Comment
     - Date
     - User info
   - "Write a Review" button

8. **Similar Venues**
   - Cards of other venues nearby or with similar quizzes
   - "More like this" section

9. **Call-to-Action**
   - "Attend this quiz" button
   - Add to calendar option
   - Get reminders toggle

### 5. Search Results Page

Filtered view of venues/events based on user search.

#### Elements:

1. **Search Parameters**
   - Current search query display
   - Filter panel with:
     - Day of week selector
     - Time range slider
     - Price range selector
     - Rating filter
     - Distance slider
     - Special features checkboxes

2. **Results Display**
   - Toggle between map and list view
   - Sorting options (relevance, distance, rating)
   - Result count

3. **Result Cards**
   - Venue image
   - Basic details
   - Match indicators (why this result was shown)
   - Quick-action buttons

4. **Pagination Controls**
   - Page numbers
   - Results per page selector

### 6. User Profile Page

User's saved venues and preferences.

#### Elements:

1. **User Header**
   - Profile image
   - Username
   - Member since date
   - Stats (venues visited, reviews written)

2. **Saved Venues**
   - Grid of favorited venues
   - Quick filters for day/location
   - Remove option

3. **Attendance History**
   - Timeline of visited venues
   - Rating given
   - Option to write/edit review

4. **Preferences Section**
   - Preferred quiz types
   - Notification settings
   - Location preferences

5. **Friends Activity**
   - Feed of friends' recent trivia activities
   - Invite friends section

## Design System

### Colors

- **Primary**: [Color code] - Used for primary buttons, links, and key UI elements
- **Secondary**: [Color code] - Used for secondary actions and highlights
- **Accent**: [Color code] - Used sparingly for attention-grabbing elements
- **Background**: [Color code] - Main page background
- **Surface**: [Color code] - Cards and elevated surfaces
- **Text**: [Color codes for primary/secondary text]
- **Success/Error/Warning**: [Color codes for feedback states]

### Typography

- **Headings**: [Font family] - Bold, confident headings for page titles and section headers
- **Body**: [Font family] - Readable, clear font for main content
- **Accents**: [Font family] - Optional stylized font for special elements

### Components

1. **Venue Cards**
   - Consistent layout across all pages
   - Clear hierarchy of information
   - Interactive elements (save, share, view)

2. **Event Timeline**
   - Clear day/date indicators
   - Compact but readable event listings
   - Visual indicators for event status

3. **Maps**
   - Consistent pin design
   - Clear popup information
   - Smooth zoom and interaction

4. **Navigation**
   - Sticky header with key navigation
   - Breadcrumb system for deep pages
   - Mobile-friendly menu

## Mobile Considerations

1. **Responsive Design**
   - All pages adapt to mobile screens
   - Touch-friendly controls
   - Collapsible sections

2. **Mobile-Specific Features**
   - "Near Me" button using geolocation
   - Swipeable cards
   - Bottom navigation bar
   - Share to social media integration

## User Flow Diagrams

1. **Finding a Trivia Night**
   - Home → Search → Results → Venue Detail

2. **Exploring by Location**
   - Home → Country → City → Venue

3. **User Account Journey**
   - Signup/Login → Profile Setup → Save Venues → Attend Events → Review

## Schema Integration

This design incorporates data from the following schema elements:

1. **Venues**
   - name
   - address
   - phone
   - website
   - description
   - hero_image_url
   - latitude/longitude
   - google_place_id

2. **Events**
   - name
   - day_of_week
   - start_time
   - frequency (weekly, biweekly, monthly, irregular)
   - entry_fee_cents
   - description

3. **Cities**
   - name
   - country association

4. **Countries**
   - name
   - code

5. **Sources**
   - name
   - website_url

## Implementation Notes

1. All interactive elements should provide immediate feedback
2. Maps should load progressively and cache data where possible
3. Events should be sorted by relevance to user (location, preferences)
4. Image lazy-loading should be implemented for performance
5. Server-side rendering for SEO benefits 