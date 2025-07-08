import time
import json # Added for saving events to a file
import platform # For OS detection
import sys # For platform checking
from pynput import mouse, keyboard

# Global list to store recorded events
recorded_events = []
# Variable to store the timestamp of the last event
last_event_time = None
# Flag to indicate if recording is active
is_recording = False

def get_event_time():
    """Returns the current time relative to the start of the recording or the last event."""
    global last_event_time
    current_time = time.time()
    if last_event_time is None:
        # For the first event, record its timestamp as the base
        last_event_time = current_time
        return 0.0  # No delay for the first event
    else:
        delay = current_time - last_event_time
        last_event_time = current_time
        return delay

# --- Mouse Event Callbacks ---
def on_move(x, y):
    if is_recording:
        delay = get_event_time()
        event_data = {'type': 'mouse_move', 'x': x, 'y': y, 'time': delay, 'timestamp': time.time()}
        recorded_events.append(event_data)
        print(f"Recorded: {event_data}")

def on_click(x, y, button, pressed):
    if is_recording:
        delay = get_event_time()
        event_type = 'mouse_press' if pressed else 'mouse_release'
        event_data = {'type': event_type, 'x': x, 'y': y, 'button': str(button), 'time': delay, 'timestamp': time.time()}
        recorded_events.append(event_data)
        print(f"Recorded: {event_data}")

def on_scroll(x, y, dx, dy):
    if is_recording:
        delay = get_event_time()
        event_data = {'type': 'mouse_scroll', 'x': x, 'y': y, 'dx': dx, 'dy': dy, 'time': delay, 'timestamp': time.time()}
        recorded_events.append(event_data)
        print(f"Recorded: {event_data}")

# --- Keyboard Event Callbacks ---
def on_press(key):
    if is_recording:
        delay = get_event_time()
        try:
            event_data = {'type': 'key_press', 'key': key.char, 'time': delay, 'timestamp': time.time()}
        except AttributeError:
            event_data = {'type': 'key_press', 'key': str(key), 'time': delay, 'timestamp': time.time()}
        recorded_events.append(event_data)
        print(f"Recorded: {event_data}")

def on_release(key):
    global is_recording, mouse_listener, keyboard_listener
    if key == keyboard.Key.esc:
        print("Recording stopped by ESC key.")
        is_recording = False
        # Stop listeners
        if mouse_listener:
            mouse_listener.stop()
        if keyboard_listener:
            keyboard_listener.stop()
        return False # Stop the keyboard listener

    if is_recording:
        delay = get_event_time()
        try:
            event_data = {'type': 'key_release', 'key': key.char, 'time': delay, 'timestamp': time.time()}
        except AttributeError:
            event_data = {'type': 'key_release', 'key': str(key), 'time': delay, 'timestamp': time.time()}
        recorded_events.append(event_data)
        print(f"Recorded: {event_data}")


# --- Main Recording Logic ---
mouse_listener = None
keyboard_listener = None

def start_recording():
    global recorded_events, last_event_time, is_recording, mouse_listener, keyboard_listener

    recorded_events = []
    last_event_time = None # Reset last event time for new recording
    is_recording = True
    print("Recording started... Press ESC to stop.")

    # Setup and start mouse listener
    mouse_listener = mouse.Listener(
        on_move=on_move,
        on_click=on_click,
        on_scroll=on_scroll
    )
    mouse_listener.start()

    # Setup and start keyboard listener
    keyboard_listener = keyboard.Listener(
        on_press=on_press,
        on_release=on_release
    )
    keyboard_listener.start()

    # Keep the main thread alive while listeners are running
    # Listeners will be stopped by on_release callback when Esc is pressed
    if mouse_listener: # Ensure listener exists before joining
        mouse_listener.join()
    if keyboard_listener: # Ensure listener exists before joining
        keyboard_listener.join()

    print("Recording finished.")
    print(f"Total events recorded: {len(recorded_events)}")
    return recorded_events # Return the recorded events

def display_recorded_events(events, filename=None):
    """
    Displays recorded events in a structured format and optionally saves them to a JSON file.

    Args:
        events (list): The list of recorded event dictionaries.
        filename (str, optional): If provided, events will be saved to this file as JSON.
                                   Defaults to None (no saving).
    """
    print("\n--- Detailed Recorded Events ---")
    if not events:
        print("No events were recorded or provided.")
        return

    for i, event in enumerate(events):
        event_time_str = f"{event['time']:.4f}s"
        event_details = {k: v for k, v in event.items() if k not in ['time', 'timestamp']}
        # Ensure button is a string for JSON serialization if it's not already
        if 'button' in event_details and not isinstance(event_details['button'], str):
            event_details['button'] = str(event_details['button'])
        # Ensure key is a string for JSON serialization
        if 'key' in event_details and not isinstance(event_details['key'], str):
            event_details['key'] = str(event_details['key'])

        print(f"Event {i+1:03d}: Delay={event_time_str:<10} Type={event['type']:<15} Details: {event_details}")

    if filename:
        try:
            # Prepare events for JSON serialization (ensure all parts are serializable)
            serializable_events = []
            for event in events:
                e_copy = event.copy()
                if 'button' in e_copy and not isinstance(e_copy['button'], (str, int, float, bool, type(None))):
                    e_copy['button'] = str(e_copy['button'])
                if 'key' in e_copy and not isinstance(e_copy['key'], (str, int, float, bool, type(None))):
                    e_copy['key'] = str(e_copy['key'])
                serializable_events.append(e_copy)

            with open(filename, 'w') as f:
                json.dump(serializable_events, f, indent=4)
            print(f"\nSuccessfully saved {len(serializable_events)} events to {filename}")
        except Exception as e:
            print(f"\nError saving events to {filename}: {e}")

# --- Event Playback Logic ---
def parse_key(key_str):
    """Converts a key string back to a pynput Key object or char."""
    if key_str.startswith("Key."):
        key_name = key_str.split('.')[1]
        return getattr(keyboard.Key, key_name)
    elif len(key_str) == 1: # Handles simple characters like 'a', '1', etc.
        return key_str
    elif key_str.startswith("'") and key_str.endswith("'") and len(key_str) == 3: # Handles quoted characters like "'a'"
        return key_str[1]
    else: # For special keys that might not be in Key enum directly but are string representations from pynput
        # This part might need refinement based on how different special keys are stored.
        # For now, if it's not a Key enum member and not a single char, we try to use it as is.
        # This could be problematic for complex keys not directly usable by controller.press/release.
        # A more robust solution might involve a mapping for special key strings if direct getattr fails.
        try:
            # Attempt to map to KeyCode if it's a vk representation or similar
            return keyboard.KeyCode.from_char(key_str)
        except:
            # Fallback for other cases, though this might lead to errors if not a valid key for controller
            print(f"Warning: Unhandled key string format for playback: {key_str}. Attempting to use as is.")
            return key_str


def parse_button(button_str):
    """Converts a button string back to a pynput Button object."""
    # Example: "Button.left" -> pynput.mouse.Button.left
    if button_str.startswith("Button."):
        button_name = button_str.split('.')[1]
        return getattr(mouse.Button, button_name)
    return None # Should not happen if data is saved correctly

def playback_events(events_data):
    """
    Plays back a list of recorded mouse and keyboard events.

    Args:
        events_data (list): A list of event dictionaries.
    """
    if not events_data:
        print("No events to play back.")
        return

    print("\n--- Starting Playback ---")
    mouse_controller = mouse.Controller()
    keyboard_controller = keyboard.Controller()

    # Store initial mouse position to handle relative first move if necessary
    # However, recorded moves are absolute, so this might not be strictly needed
    # unless the first event is a relative move (which our recorder doesn't create).

    for i, event in enumerate(events_data):
        delay = event.get('time', 0) # Get delay, default to 0 if not present

        # The first event's delay is relative to the start of recording (should be 0 or small).
        # Subsequent event delays are relative to the previous event.
        if i == 0 and delay > 0.1: # If first event has a significant "delay", it's likely from manual start
            print(f"Note: First event has a delay of {delay:.2f}s. This delay will be observed.")

        time.sleep(delay)

        event_type = event['type']
        print(f"Playing event {i+1}/{len(events_data)}: {event_type}, Delay: {delay:.4f}s")

        if event_type == 'mouse_move':
            mouse_controller.position = (event['x'], event['y'])
        elif event_type == 'mouse_press':
            button = parse_button(event['button'])
            if button:
                mouse_controller.position = (event['x'], event['y']) # Ensure cursor is at the right spot
                mouse_controller.press(button)
        elif event_type == 'mouse_release':
            button = parse_button(event['button'])
            if button:
                mouse_controller.position = (event['x'], event['y']) # Ensure cursor is at the right spot
                mouse_controller.release(button)
        elif event_type == 'mouse_scroll':
            mouse_controller.position = (event['x'], event['y']) # Ensure cursor is at the right spot
            mouse_controller.scroll(event['dx'], event['dy'])
        elif event_type == 'key_press':
            key = parse_key(event['key'])
            keyboard_controller.press(key)
        elif event_type == 'key_release':
            key = parse_key(event['key'])
            keyboard_controller.release(key)
        else:
            print(f"Warning: Unknown event type '{event_type}' encountered during playback.")

    print("--- Playback Finished ---")


if __name__ == "__main__":
    print("Event Recorder Script")

    # --- Configuration ---
    ACTION = "record"  # Options: "record", "playback", "record_and_playback"
    EVENTS_FILENAME = "recorded_events.json"

    if ACTION == "record" or ACTION == "record_and_playback":
        print(f"Starting recording. Press ESC to stop. Events will be saved to {EVENTS_FILENAME}")
        recorded_data = start_recording()

        if recorded_data:
            display_recorded_events(recorded_data, filename=EVENTS_FILENAME)

            if ACTION == "record_and_playback":
                input("Press Enter to start playback of the recorded session...")
                playback_events(recorded_data)
        else:
            print("No events were recorded.")

    elif ACTION == "playback":
        print(f"Attempting to playback events from {EVENTS_FILENAME}")
        try:
            with open(EVENTS_FILENAME, 'r') as f:
                events_to_play = json.load(f)
            if events_to_play:
                input("Press Enter to start playback...")
                playback_events(events_to_play)
            else:
                print(f"No events found in {EVENTS_FILENAME} or file is empty.")
        except FileNotFoundError:
            print(f"Error: Events file '{EVENTS_FILENAME}' not found. Please record events first.")
        except json.JSONDecodeError:
            print(f"Error: Could not decode JSON from '{EVENTS_FILENAME}'. File might be corrupted.")
        except Exception as e:
            print(f"An unexpected error occurred during playback setup: {e}")
    else:
        print(f"Unknown action: {ACTION}. Please choose 'record', 'playback', or 'record_and_playback'.")
