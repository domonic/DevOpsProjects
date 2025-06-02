from flask import Flask, request, jsonify
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)

# In-memory user store
users = [
    {
        'id': 1,
        'username': 'admin',
        'password': generate_password_hash('admin123')
    }
]

@app.route('/')
def home():
    return "Welcome to the User API!"

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'OK', 'message': 'API is healthy'}), 200


@app.route('/signup', methods=['POST'])
def signup():
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({'error': 'Username and password required'}), 400

    # Check if user already exists
    if any(user['username'] == data['username'] for user in users):
        return jsonify({'error': 'Username already exists'}), 409

    new_id = max([user['id'] for user in users], default=0) + 1
    hashed_password = generate_password_hash(data['password'])
    new_user = {
        'id': new_id,
        'username': data['username'],
        'password': hashed_password
    }
    users.append(new_user)

    return jsonify({'message': 'User created successfully', 'user_id': new_user['id']}), 201

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({'error': 'Username and password required'}), 400

    user = next((user for user in users if user['username'] == data['username']), None)
    if user and check_password_hash(user['password'], data['password']):
        return jsonify({'message': 'Login successful'}), 200
    return jsonify({'error': 'Invalid username or password'}), 401

if __name__ == '__main__':
    app.run(debug=True)
