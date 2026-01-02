#!/usr/bin/env python3
"""
Enhanced test script to verify LiteLLM Redis caching behavior.
This will send identical requests with timing and wait for cache hits.
"""

import time
import json
import subprocess
import sys

def test_caching_with_timing():
    """Test caching with timing to observe cache hits"""
    
    # Test prompt
    test_prompt = "What is the capital of France? Please respond with just 'Paris'."
    
    print(f"Testing caching with prompt: '{test_prompt}'")
    print("=" * 70)
    
    # Get initial cache stats
    cache_stats_before = get_redis_cache_stats()
    print(f"Initial cache hits: {cache_stats_before.get('keyspace_hits', 0)}")
    print(f"Initial cache misses: {cache_stats_before.get('keyspace_misses', 0)}")
    
    # Send first request (should trigger cache miss + store)
    print("\n--- Request 1: First time (cache miss) ---")
    response1 = make_cached_request(test_prompt)
    
    # Wait a moment for cache to be stored
    time.sleep(2)
    
    # Send identical request immediately (should hit cache)
    print("\n--- Request 2: Identical, immediate (should hit cache) ---")
    response2 = make_cached_request(test_prompt)
    
    # Wait longer, then send again (should still hit cache if TTL allows)
    print("\n--- Request 3: Identical, after delay (should hit cache) ---")
    time.sleep(5)
    response3 = make_cached_request(test_prompt)
    
    # Final cache stats
    cache_stats_after = get_redis_cache_stats()
    print("\n" + "=" * 70)
    print("CACHE ANALYSIS")
    print("=" * 70)
    
    cache_hits = cache_stats_after.get('keyspace_hits', 0) - cache_stats_before.get('keyspace_hits', 0)
    cache_misses = cache_stats_after.get('keyspace_misses', 0) - cache_stats_before.get('keyspace_misses', 0)
    
    print(f"Cache hits: {cache_hits}")
    print(f"Cache misses: {cache_misses}")
    
    # Analyze responses
    analyze_responses([response1, response2, response3], cache_hits)
    
    # Check Redis keys
    print(f"\nTotal Redis keys: {len(get_redis_keys())}")
    
def make_cached_request(prompt):
    """Make a single request and return response"""
    cmd = [
        'curl', '-s', '-X', 'POST',
        'http://localhost:4000/v1/chat/completions',
        '-H', 'Content-Type: application/json',
        '-H', 'Authorization: Bearer sk-vyNAFniOpGjMaWdoMcGQQg',
        '-d', json.dumps({
            "model": "local-glm-4-5-air-mlx",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.1,
            "max_tokens": 10
        })
    ]
    
    try:
        start_time = time.time()
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        end_time = time.time()
        
        if result.returncode == 0:
            response = json.loads(result.stdout)
            
            # Extract key info
            tokens_used = response.get('usage', {}).get('total_tokens', 0)
            model = response.get('model', 'unknown')
            elapsed_time = end_time - start_time
            
            print(f"[OK] Success")
            print(f"  Model: {model}")
            print(f"  Tokens used: {tokens_used}")
            print(f"  Response time: {elapsed_time:.2f}s")
            
            return {
                'response': response,
                'model': model,
                'tokens_used': tokens_used,
                'response_time': elapsed_time
            }
        else:
            print(f" Failed: {result.stderr}")
            return None
            
    except Exception as e:
        print(f" Error: {e}")
        return None

def analyze_responses(responses, cache_hits):
    """Analyze responses for caching behavior"""
    
    if not responses or None in responses:
        print(" Some requests failed, cannot analyze")
        return
    
    # Check if responses are identical (strong indicator of cache hit)
    content1 = responses[0]['response'].get('choices', [{}])[0].get('message', {}).get('content')
    content2 = responses[1]['response'].get('choices', [{}])[0].get('message', {}).get('content')
    content3 = responses[2]['response'].get('choices', [{}])[0].get('message', {}).get('content')
    
    print(f"\nResponse Analysis:")
    print(f"  Request 1 content: '{content1}'")
    print(f"  Request 2 content: '{content2}'")  
    print(f"  Request 3 content: '{content3}'")
    
    are_identical = all(content1.strip() == c.strip() for c in [content2, content3] if c)
    
    print(f"  All responses identical: {are_identical}")
    
    # Check response times (cache hits should be faster)
    print(f"\nResponse Times:")
    for i, resp in enumerate(responses):
        if resp:
            print(f"  Request {i+1}: {resp['response_time']:.2f}s")
    
    # Interpret results
    print(f"\nInterpretation:")
    if cache_hits > 0:
        print("[OK] Cache hits detected - caching is working")
    else:
        if are_identical:
            print(" Responses identical but no cache hits detected")
            print("  This could indicate:")
            print("  - Cache keys are being generated differently than expected")
            print("  - TTL is very short and entries expire quickly")
            print("  - Cache configuration needs adjustment")
        else:
            print(" No cache hits and responses differ")

def get_redis_cache_stats():
    """Get Redis statistics"""
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

def get_redis_keys():
    """Get all Redis keys"""
    try:
        result = subprocess.run(['redis-cli', 'keys', '*'], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip().split('\n') if result.stdout.strip() else []
    except Exception as e:
        print(f"Error getting Redis keys: {e}")
    
    return []

def check_redis_connection():
    """Check if Redis is accessible"""
    try:
        result = subprocess.run(['redis-cli', 'ping'], capture_output=True, text=True)
        return result.returncode == 0 and result.stdout.strip() == 'PONG'
    except:
        return False

if __name__ == "__main__":
    print("Enhanced LiteLLM Caching Test Script")
    print("=" * 70)
    
    if not check_redis_connection():
        print(" Redis is not accessible")
        sys.exit(1)
    
    print("[OK] Redis connection OK")
    test_caching_with_timing()