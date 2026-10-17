"""Development entry point; production uses passenger_wsgi.application."""
import os
from wsgiref.simple_server import make_server
from passenger_wsgi import application, validate_result, load_results

if __name__ == '__main__':
    with make_server('127.0.0.1',int(os.environ.get('PORT','3001')),application) as server:
        server.serve_forever()
