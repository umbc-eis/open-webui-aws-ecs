import requests
import os
import json
import argparse
import sys
import time
import getpass

# --- Configuration ---
# Load from environment variables
LITELLM_URL = os.getenv("LITELLM_URL")
OPENWEBUI_URL = os.getenv("OPENWEBUI_URL")
LITELLM_ADMIN_KEY = os.getenv("LITELLM_ADMIN_KEY")
OPENWEBUI_ADMIN_TOKEN = os.getenv("OPENWEBUI_ADMIN_TOKEN")

# Default settings for new users (if no budget specified)
DEFAULT_BUDGET = None  # No default budget unless specified

def get_team_id_from_alias(team_alias):
    """Looks up a team ID from its alias."""
    try:
        resp = requests.get(
            f"{LITELLM_URL}/team/list",
            headers={"Authorization": f"Bearer {LITELLM_ADMIN_KEY}"}
        )
        resp.raise_for_status()
        teams = resp.json()

        for team in teams:
            if team.get("team_alias") == team_alias:
                return team.get("team_id")

        # If not found, return the original value (might already be an ID)
        return team_alias
    except Exception as e:
        print(f"[LiteLLM] Warning: Could not look up team alias, using value as-is: {e}", file=sys.stderr)
        return team_alias

def create_litellm_user(user_id, team_id, budget_amount, budget_duration):
    """Creates a new user in LiteLLM and returns the auto-generated API key.

    Args:
        user_id: User email/ID
        team_id: Team ID or alias
        budget_amount: Budget amount (None for no budget)
        budget_duration: Budget duration like "1d" or "30d" (None for no budget)

    Returns None if the user already exists.
    """
    print(f"[LiteLLM] Attempting to create user: {user_id}...")

    # Convert team alias to team ID if needed
    actual_team_id = get_team_id_from_alias(team_id) if team_id else None
    if actual_team_id != team_id:
        print(f"[LiteLLM] Resolved team '{team_id}' to ID: {actual_team_id}")

    payload = {
        "user_id": user_id,
        "user_email": user_id,  # Use email as user_id
        "teams": [actual_team_id] if actual_team_id else [],
        "team_id": actual_team_id,  # Set team_id for the auto-created key (deprecated but needed)
        "models": ["all-team-models"],  # Allow access to all team models instead of personal models
        "auto_create_key": True,  # Automatically create an API key
        "key_alias": f"{user_id}-default",  # Set alias for easy identification
        "user_role": "internal_user"  # Standard internal user role
    }

    # Add budget if specified
    if budget_amount is not None and budget_duration is not None:
        payload["max_budget"] = budget_amount
        payload["budget_duration"] = budget_duration
        print(f"[LiteLLM] Setting budget: ${budget_amount} per {budget_duration}")
    try:
        resp = requests.post(
            f"{LITELLM_URL}/user/new",
            headers={
                "Authorization": f"Bearer {LITELLM_ADMIN_KEY}",
                "Content-Type": "application/json"
            },
            data=json.dumps(payload)
        )
        resp.raise_for_status()
        result = resp.json()
        api_key = result.get("key")
        print(f"[LiteLLM] User '{user_id}' created successfully")
        print(f"[LiteLLM] API key generated for user '{user_id}'")
        return api_key
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 400:
            error_text = e.response.text
            if "already exists" in error_text.lower():
                print(f"[LiteLLM] User '{user_id}' already exists")
                return None
        # Re-raise for any other error
        raise e

def delete_litellm_user(user_id):
    """Deletes a LiteLLM user. Used for rolling back a failed creation."""
    payload = {"user_id": user_id}
    print(f"[LiteLLM] ROLLBACK: Attempting to delete user: {user_id}...")
    try:
        resp = requests.post(
            f"{LITELLM_URL}/user/delete",
            headers={
                "Authorization": f"Bearer {LITELLM_ADMIN_KEY}",
                "Content-Type": "application/json"
            },
            data=json.dumps(payload)
        )
        resp.raise_for_status()
        print(f"[LiteLLL] ROLLBACK: Successfully deleted user '{user_id}'.")
    except Exception as e:
        print(f"!!! ROLLBACK FAILED: Could not delete LiteLLM user {user_id}. Please check manually. Error: {e}", file=sys.stderr)

def create_openwebui_user(user_id, user_email, is_admin=False, password=None):
    """Creates a new user in Open WebUI and returns the password used."""
    print(f"[Open WebUI] Attempting to create user: {user_id}...")

    # If no password provided, generate a random one
    if not password:
        import secrets
        import string
        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = ''.join(secrets.choice(alphabet) for i in range(48))
        print(f"[Open WebUI] Generated 48-character temporary password for user (user should change this on first login)")

    user_role = "admin" if is_admin else "user"
    payload = {
        "email": user_email,
        "password": password,
        "name": user_id,  # Use email as name for now
        "role": user_role
    }
    create_resp = requests.post(
        f"{OPENWEBUI_URL}/api/v1/auths/add",
        headers={
            "Authorization": f"Bearer {OPENWEBUI_ADMIN_TOKEN}",
            "Content-Type": "application/json"
        },
        data=json.dumps(payload)
    )
    create_resp.raise_for_status()
    print(f"[Open WebUI] User '{user_id}' created with role: {user_role}")
    return password  # Return the password so it can be used for login

def create_openwebui_connection(user_id, user_email, user_password, api_key):
    """Configures a LiteLLM direct connection in the user's settings.

    This requires logging in as the user to update their settings.
    """
    print(f"[Open WebUI] Attempting to configure direct connection for: {user_id}...")

    # Login as the new user to get their auth token
    login_resp = requests.post(
        f"{OPENWEBUI_URL}/api/v1/auths/signin",
        headers={"Content-Type": "application/json"},
        data=json.dumps({"email": user_email, "password": user_password})
    )
    login_resp.raise_for_status()
    user_token = login_resp.json()["token"]

    # Prepare the settings with direct connection
    settings = {
        "ui": {
            "directConnections": {
                "OPENAI_API_BASE_URLS": [LITELLM_URL],
                "OPENAI_API_KEYS": [api_key],
                "OPENAI_API_CONFIGS": [{
                    "auth_type": "bearer",
                    "connection_type": "external",
                    "enable": True,
                    "model_ids": [],
                    "prefix_id": "",
                    "tags": []
                }]
            }
        }
    }

    # Update the user's settings using their token
    update_resp = requests.post(
        f"{OPENWEBUI_URL}/api/v1/users/user/settings/update",
        headers={
            "Authorization": f"Bearer {user_token}",
            "Content-Type": "application/json"
        },
        data=json.dumps(settings)
    )
    update_resp.raise_for_status()
    print(f"[Open WebUI] Direct connection configured for user '{user_id}'")

def check_litellm_user_exists(user_id):
    """Checks if a user already exists in LiteLLM.

    Note: LiteLLM's /user/info endpoint is unreliable (returns 200 for both existing
    and non-existing users). We skip the check and handle duplicates during creation instead.
    """
    # Always return False - we'll check during creation attempt
    return False

def check_openwebui_user_exists(user_id):
    """Checks if a user already exists in Open WebUI by email."""
    print(f"[Open WebUI] Checking if user '{user_id}' exists...")
    try:
        # IMPORTANT: The trailing slash is required for the API to work correctly
        # Note: The email query parameter doesn't work reliably in Open WebUI 0.6.34,
        # so we fetch all users and filter client-side
        resp = requests.get(
            f"{OPENWEBUI_URL}/api/v1/users/",  # Note the trailing slash
            headers={"Authorization": f"Bearer {OPENWEBUI_ADMIN_TOKEN}"}
        )
        resp.raise_for_status()

        data = resp.json()

        # Filter users by email client-side since the API query param doesn't work reliably
        if data and "users" in data:
            for user in data["users"]:
                if user.get("email") == user_id:
                    return True

        return False

    except requests.exceptions.HTTPError as e:
        print(f"!!! Error checking Open WebUI user: {e.response.text}", file=sys.stderr)
        raise e
    except json.JSONDecodeError:
        print(f"!!! Error: Received non-JSON response from Open WebUI API.", file=sys.stderr)
        raise Exception("Open WebUI API did not return valid JSON. Check URL and server status.")
    except Exception as e:
        print(f"!!! An unexpected error occurred checking Open WebUI user: {e}", file=sys.stderr)
        raise e

def process_user(username, team_id, daily_budget, monthly_budget, is_admin, skip_litellm=False):
    """Runs the full provisioning process for a single user."""

    team_display_name = team_id
    if skip_litellm:
        team_display_name = team_id or "N/A (Skipped)"

    # Determine budget amount and duration
    budget_amount = None
    budget_duration = None
    budget_display = "No budget"

    if daily_budget is not None:
        budget_amount = daily_budget
        budget_duration = "1d"
        budget_display = f"${daily_budget:.2f}/day"
    elif monthly_budget is not None:
        budget_amount = monthly_budget
        budget_duration = "30d"
        budget_display = f"${monthly_budget:.2f}/month"

    print(f"\n--- Processing User: {username} (Team: {team_display_name}, Budget: {budget_display}) ---")
    
    litellm_user_created = False  # State tracking for rollback
    user_id = username
    user_email = username
    api_key = None

    try:
        # --- Pre-flight Checks ---
        litellm_exists = False
        if not skip_litellm:
            litellm_exists = check_litellm_user_exists(user_id)
        
        webui_exists = check_openwebui_user_exists(user_id)

        if litellm_exists or webui_exists:
            print(f"!!! SKIPPING: User '{user_id}' already exists on one or more platforms.")
            if litellm_exists:
                print(f"[LiteLLM] User found (run with --skip-litellm to ignore this check and provision on Open WebUI only).")
            if webui_exists:
                print(f"[Open WebUI] User found.")
            print(f"--- Finished processing user: {username} ---")
            return  # Stop processing this user

        # --- Creation Process (Now with rollback and skip logic) ---
        print(f"User '{user_id}' not found on required platforms. Proceeding with creation...")

        if not skip_litellm:
            # Step 1: Create LiteLLM User (also generates API key)
            api_key = create_litellm_user(user_id, team_id, budget_amount, budget_duration)

            if api_key is None:
                # User already exists in LiteLLM
                print(f"!!! SKIPPING: User '{user_id}' already exists in LiteLLM.")
                print(f"--- Finished processing user: {username} ---")
                return

            litellm_user_created = True  # Mark this step as complete
        else:
            print("[LiteLLM] Skipping LiteLLM creation and key generation as requested.")
            api_key = getpass.getpass(f"[Input] Enter pre-existing LiteLLM API key for {user_id}: ")
            if not api_key:
                raise ValueError("API Key cannot be empty when --skip-litellm is used.")

        # Step 3: Create Open WebUI User
        user_password = create_openwebui_user(user_id, user_email, is_admin)

        # Step 4: Create Open WebUI Connection
        create_openwebui_connection(user_id, user_email, user_password, api_key)
        
        print(f"--- Successfully processed user: {username} ---")
        
    except Exception as e:
        print(f"!!! An unexpected error occurred processing user {username}: {e}", file=sys.stderr)
        if isinstance(e, requests.exceptions.HTTPError):
            # Don't print the response text if it's what we just caught (JSONDecodeError)
            if "JSONDecodeError" not in str(e):
                print(f"!!! Response Body: {e.response.text}", file=sys.stderr)

        # --- ROLLBACK LOGIC ---
        # If the LiteLLM user was created but something failed after, undo it.
        if litellm_user_created:
            print(f"--- Attempting rollback for user {user_id} ---")
            delete_litellm_user(user_id)
        else:
            print(f"--- No rollback needed (LiteLLM user was not created) ---")
        
        print(f"--- Finished processing user: {username} (with errors) ---")


def main():
    """Parses command-line arguments and processes one or more users."""
    global LITELLM_URL, OPENWEBUI_URL
    
    # Check for required environment variables
    # We will check these *after* parsing args, to allow flags to override
    # LITELLM_ADMIN_KEY (set via env var only)
    # OPENWEBUI_ADMIN_TOKEN (set via env var only)
    
    help_epilog = f"""
-----------------
Usage Examples:
-----------------

1. Provision a single user (using env vars for URLs):
   export LITELLM_URL=http://localhost:4000
   export OPENWEBUI_URL=http://localhost:8080
   export LITELLM_ADMIN_KEY=your_litellm_admin_key
   export OPENWEBUI_ADMIN_TOKEN=your_webui_token
   python provision_user.py --username user@example.com --team-id "student_team"

2. Provision multiple users (using flags for URLs):
   (Create a file named users.txt with one email per line)
   export LITELLM_ADMIN_KEY=your_litellm_admin_key
   export OPENWEBUI_ADMIN_TOKEN=your_webui_token
   python provision_user.py --file users.txt --team-id "student_team" --litellm-url "http://lite.example.com" --openwebui-url "http://webui.example.com"

3. Provision a single user with a daily budget:
   (Env vars set as in example 1)
   python provision_user.py --username vip@example.com --team-id "vip_team" --daily-budget 5.00

4. Provision a single user with a monthly budget:
   (Env vars set as in example 1)
   python provision_user.py --username student@example.com --team-id "student_team" --monthly-budget 15.00

5. Provision a user with no budget limit:
   (Env vars set as in example 1)
   python provision_user.py --username unlimited@example.com --team-id "faculty_team"

6. Provision a new admin user:
   (Env vars set as in example 1)
   python provision_user.py --username admin@example.com --team-id "admin_team" --admin

7. Provision Open WebUI only (skipping LiteLLM):
   (Env vars set as in example 1)
   python provision_user.py --username user@example.com --skip-litellm --litellm-url "http://localhost:4000"
   (You will be prompted to enter the API key)

Important:
The following configuration items are ALWAYS required, via flag or env var:
- --litellm-url (or LITELLM_URL env var) - *Also required with --skip-litellm to configure the Open WebUI connection URL*
- --openwebui-url (or OPENWEBUI_URL env var)

The following MUST be set as environment variables:
- OPENWEBUI_ADMIN_TOKEN (ALWAYS required - use the "API Key" from Account Settings, NOT the JWT Token)
- LITELLM_ADMIN_KEY (Required unless --skip-litellm is used)

The following MUST be set as a flag:
- --team-id (Required unless --skip-litellm is used)
"""

    parser = argparse.ArgumentParser(
        description="Provision new users for LiteLLM and Open WebUI.",
        epilog=help_epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    # --- User Input (Required) ---
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "-u", "--username",
        help="A single username (email) to provision."
    )
    group.add_argument(
        "-f", "--file",
        help="A file containing a list of usernames (emails), one per line."
    )
    
    # --- Configuration ---
    parser.add_argument(
        "-t", "--team-id",
        help="The LiteLLM Team ID to assign users to. (Required unless --skip-litellm is used)",
        required=False # No longer universally required
    )
    
    # --- Configuration (Optional, with env var fallback) ---
    parser.add_argument(
        "--litellm-url",
        default=LITELLM_URL,
        help="The URL for the LiteLLM admin endpoint (e.g., http://localhost:4000). Overrides LITELLM_URL env var. *Also required when skipping LiteLLM to set the Open WebUI connection URL.*"
    )
    parser.add_argument(
        "--openwebui-url",
        default=OPENWEBUI_URL,
        help="The URL for the Open WebUI instance (e.g., http://localhost:8080). Overrides OPENWEBUI_URL env var."
    )
    
    # --- User Settings (Optional) ---
    parser.add_argument(
        "-b", "--daily-budget",
        type=float,
        default=None,
        help="The daily budget in USD for new users. Cannot be used with --monthly-budget."
    )
    parser.add_argument(
        "-m", "--monthly-budget",
        type=float,
        default=None,
        help="The monthly (30-day) budget in USD for new users. Cannot be used with --daily-budget."
    )
    parser.add_argument(
        "-a", "--admin",
        action="store_true",
        help="Create the user as an ADMIN in Open WebUI (default: user)."
    )
    parser.add_argument(
        "--skip-litellm",
        action="store_true",
        help="Skip LiteLLM user creation and key generation. You will be prompted for an existing API key."
    )
    
    args = parser.parse_args()

    # --- Conditional Validation ---
    if not args.skip_litellm and not args.team_id:
        print("Error: --team-id is required when --skip-litellm is not used.", file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    # Validate budget arguments
    if args.daily_budget is not None and args.monthly_budget is not None:
        print("Error: Cannot specify both --daily-budget and --monthly-budget. Choose one.", file=sys.stderr)
        sys.exit(1)

    # Update global config from args (which default to env vars)
    # This makes them available to all functions
    LITELLM_URL = args.litellm_url
    OPENWEBUI_URL = args.openwebui_url

    # --- Validate Configuration ---
    missing_vars = []

    # --- Conditional LiteLLM Admin Key Check ---
    if not args.skip_litellm:
        if not LITELLM_ADMIN_KEY:
            missing_vars.append("LITELLM_ADMIN_KEY (set via env var only)")
    
    # --- Unconditional URL and Token Checks ---
    if not LITELLM_URL: # Still required for the Open WebUI connection
        missing_vars.append("LITELLM_URL (set via --litellm-url flag or env var) - *Required by Open WebUI for connection setup*")
    if not OPENWEBUI_URL:
        missing_vars.append("OPENWEBUI_URL (set via --openwebui-url flag or env var)")
    if not OPENWEBUI_ADMIN_TOKEN:
        missing_vars.append("OPENWEBUI_ADMIN_TOKEN (set via env var only)")

    if missing_vars:
        print("Error: Missing required configuration.", file=sys.stderr)
        for var in missing_vars:
            print(f"- {var}", file=sys.stderr)
        sys.exit(1)

    # --- Process Users ---
    if args.username:
        process_user(args.username, args.team_id, args.daily_budget, args.monthly_budget, args.admin, args.skip_litellm)
    elif args.file:
        try:
            with open(args.file, 'r') as f:
                for line in f:
                    username = line.strip()
                    if username:  # Skip empty lines
                        process_user(username, args.team_id, args.daily_budget, args.monthly_budget, args.admin, args.skip_litellm)
                        time.sleep(0.1) # Add a small delay to prevent rate-limiting
        except FileNotFoundError:
            print(f"Error: File not found at {args.file}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Error reading file {args.file}: {e}", file=sys.stderr)
            sys.exit(1)

if __name__ == "__main__":
    main()


