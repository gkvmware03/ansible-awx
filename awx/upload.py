from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from google.oauth2 import service_account
import os  # Import to handle file path operations

SCOPES = ['https://www.googleapis.com/auth/drive']
SERVICE_ACCOUNT_FILE = '/mnt/data/serviceaccount.json'

# Specify the target folder ID here
FOLDER_ID = '1fDZ_OUphykIVKPnx7li9Lby2UfvMBDbE'  # Replace with your Google Drive folder ID

def upload_file_as_user(file_path, user_email):
    # Get the file name from the provided file path
    file_name = os.path.basename(file_path)

    # Authenticate the service account and delegate to the user
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    delegated_credentials = credentials.with_subject(user_email)

    drive_service = build('drive', 'v3', credentials=delegated_credentials)

    # Prepare the file metadata, including the folder ID
    file_metadata = {
        'name': file_name,
        'parents': [FOLDER_ID]  # Add the file to the specified folder
    }
    media = MediaFileUpload(file_path, mimetype='application/octet-stream', resumable=True)

    # Create the file upload request
    request = drive_service.files().create(body=file_metadata, media_body=media, fields='id')

    # Perform the resumable upload
    response = None
    while response is None:
        try:
            status, response = request.next_chunk()
            if status:
                print(f"Uploaded {int(status.progress() * 100)}%")
        except Exception as e:
            print(f"An error occurred: {e}")
            print("Retrying...")
    
    print(f"File uploaded successfully. File ID: {response.get('id')}")

if __name__ == '__main__':
    import sys
    if len(sys.argv) < 3:
        print("Usage: python3 upload2.py <file_path> <user_email>")
        sys.exit(1)

    # Get the file path and user email from the command-line arguments
    file_path = sys.argv[1]
    user_email = sys.argv[2]
    
    upload_file_as_user(file_path, user_email)