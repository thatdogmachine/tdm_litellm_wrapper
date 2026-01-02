#!/usr/bin/env python3
"""
Minimal test script to verify LiteLLM Redis caching functionality.
This will send identical requests and check for cache hits/misses.
"""

import time
import json
import subprocess
import sys
from pathlib import Path

def test_caching():
    """Test caching with repeated identical requests"""
    
    # Test prompt
    test_prompt = "What is the capital of France? Please respond with just 'Paris'."
    
    print(f"Testing caching with prompt: '{test_prompt}'")
    print("=" * 60)
    
    # Send identical requests multiple times
    responses = []
    cache_stats_before = get_redis_cache_stats()
    
    for i in range(3):
        print(f"\n--- Request {i+1} ---")
        
        # Make request via curl to LiteLLM proxy with auth
        cmd = [
            'curl', '-s', '-X', 'POST',
            'http://localhost:4000/v1/chat/completions',
            '-H', 'Content-Type: application/json',
            '-H', 'Authorization: Bearer sk-vyNAFniOpGjMaWdoMcGQQg',
            '-d', json.dumps({
                "model": "local-glm-4-5-air-mlx",
                "messages": [{"role": "user", "content": test_prompt}],
                "temperature": 0.1,
                "max_tokens": 10
            })
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                response = json.loads(result.stdout)
                responses.append(response)
                
                # Extract key info from response
                tokens_used = response.get('usage', {}).get('total_tokens', 0)
                model = response.get('model', 'unknown')
                
                print(f"[OK] Request successful")
                print(f"  Model: {model}")
                print(f"  Tokens used: {tokens_used}")
                
            else:
                print(f" Request failed: {result.stderr}")
                
        except Exception as e:
            print(f" Error making request: {e}")
        
        # Small delay between requests
        time.sleep(1)
    
    cache_stats_after = get_redis_cache_stats()
    
    # Analyze results
    print("\n" + "=" * 60)
    print("CACHE ANALYSIS")
    print("=" * 60)
    
    cache_hits = cache_stats_after.get('keyspace_hits', 0) - cache_stats_before.get('keyspace_hits', 0)
    cache_misses = cache_stats_after.get('keyspace_misses', 0) - cache_stats_before.get('keyspace_misses', 0)
    
    print(f"Cache hits: {cache_hits}")
    print(f"Cache misses: {cache_misses}")
    
    if cache_hits > 0:
        print("[OK] Caching is working! Found cache hits.")
    else:
        print(" No cache hits found. Caching may not be working.")
    
    # Check if responses are identical (indicating cache hit)
    if len(responses) > 1:
        first_response = responses[0].get('choices', [{}])[0].get('message', {}).get('content')
        second_response = responses[1].get('choices', [{}])[0].get('message', {}).get('content')
        
        if first_response and second_response:
            if first_response.strip() == second_response.strip():
                print("[OK] Responses are identical - suggests caching worked")
            else:
                print(" Responses differ - may indicate no cache hits")

def get_redis_cache_stats():
    """Get Redis cache statistics"""
    try:
        result = subprocess.run(['redis-cli', 'info', 'stats'], capture_output=True, text=True)
        if result.returncode == 0:
            stats = {}
            for line in result.stdout.split('\n'):
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    stats[key] = int(value) if value.isdigit() else value
            return stats
    except Exception as e:
        print(f"Error getting Redis stats: {e}")
    
    return {}

def check_redis_connection():
    """Check if Redis is accessible"""
    try:
        result = subprocess.run(['redis-cli', 'ping'], capture_output=True, text=True)
        return result.returncode == 0 and result.stdout.strip() == 'PONG'
    except:
        return False

if __name__ == "__main__":
    print("LiteLLM Caching Test Script")
    print("=" * 60)
    
    # Check Redis connection first
    if not check_redis_connection():
        print(" Redis is not accessible or not running")
        sys.exit(1)
    
    print("[OK] Redis connection OK")
    
    # Test caching
    test_caching()
    
    print("\n" + "=" * 60)
    print("Test completed")