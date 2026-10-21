"""Serial, bounded SDK interface probe; raw responses stay in ignored output."""

import argparse
import hashlib
import http.client
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    sys.path.insert(0, str(args.sdk_root / "sdk" / "python"))
    from whisklet import bodycodec, config, profile
    from whisklet.client import build_request_headers

    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    decoded = {}
    if args.resume and (args.output / "summary.json").exists():
        results = json.loads((args.output / "summary.json").read_text(encoding="utf-8"))
        for result in results:
            if result.get('method') == 'secret_parse_api_url' and result.get('shape') == 'NoneType':
                result['ok'] = False
                result['contract_error'] = 'SDK success code with null parser data is not usable'
            path = args.output / (result["label"] + ".json")
            if result.get("method") and path.exists():
                decoded[result["label"]] = json.loads(path.read_text(encoding="utf-8"))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def persist():
        (args.output / "summary.json").write_text(
            json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def shape(value, depth=0):
        if isinstance(value, dict):
            return {key: shape(item, depth + 1) for key, item in value.items()} if depth < 2 else list(value)
        if isinstance(value, list):
            return {"type": "list", "length": len(value), "first": shape(value[0], depth + 1) if value else None}
        if isinstance(value, str):
            return {"type": "str", "length": len(value)}
        return type(value).__name__

    def call(method, data, label=None):
        time.sleep(0.4)
        label = label or method
        if label in decoded and (method != "secret_parse_api_url" or isinstance(decoded[label].get("data"), str)):
            return decoded[label]
        started = time.perf_counter()
        result = {"label": label, "method": method, "request": data, "transport": "direct", "at": time.time()}
        connection = http.client.HTTPConnection(config.HOST, config.PORT, timeout=12)
        value = None
        try:
            payload = bodycodec.encrypt_body({"method": method, "data": data, "csrf": int(time.time() * 1000)})
            connection.request("POST", config.PATH_ENTRY, payload, build_request_headers())
            response = connection.getresponse()
            raw = response.read(4 * 1024 * 1024 + 1)
            result.update(status=response.status, bytes=len(raw), headers=dict(response.getheaders()))
            (args.output / (label + ".wire.txt")).write_bytes(raw)
            if len(raw) > 4 * 1024 * 1024:
                raise ValueError("Response exceeds 4 MiB")
            value = bodycodec.decrypt_response(raw.decode("utf-8"), method)
            decoded[label] = value
            (args.output / (label + ".json")).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            result.update(code=value.get("code"), msg=value.get("msg"), meta=value.get("_meta"), shape=shape(value.get("data")))
            result["ok"] = response.status == 200 and value.get("code") == 1
            if method == "secret_parse_api_url":
                result["ok"] = result["ok"] and isinstance(value.get("data"), str) and len(value["data"]) >= 32
        except Exception as error:
            result.update(ok=False, error=type(error).__name__ + ": " + str(error))
        finally:
            connection.close()
        result["ms"] = round((time.perf_counter() - started) * 1000)
        results.append(result)
        persist()
        print(json.dumps({key: result[key] for key in ("label", "ok", "status", "code", "ms", "error") if key in result}), flush=True)
        return value or {}

    def get(url, label, limit=262144, media=False):
        started = time.perf_counter()
        result = {"label": label, "host": urllib.parse.urlparse(url).hostname, "transport": "direct"}
        try:
            headers = {"user-agent": profile.USER_AGENT}
            if media:
                headers["Range"] = "bytes=0-63"
            with opener.open(urllib.request.Request(url, headers=headers), timeout=12) as response:
                raw = response.read(limit)
                result.update(status=response.status, bytes=len(raw), content_type=response.headers.get("content-type"), ok=True)
            (args.output / (label + ".bin")).write_bytes(raw)
            result["sha256"] = hashlib.sha256(raw).hexdigest()
            text = raw.decode("utf-8", "replace")
            if not media and text.lstrip().startswith("{"):
                payload = json.loads(text)
                (args.output / (label + ".json")).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
                result["shape"] = shape(payload)
            result["hls"] = text.startswith("#EXTM3U")
            return text
        except Exception as error:
            result.update(ok=False, error=type(error).__name__ + ": " + str(error))
            return ""
        finally:
            result["ms"] = round((time.perf_counter() - started) * 1000)
            results.append(result)
            persist()
            print(json.dumps(result, ensure_ascii=False), flush=True)

    offline = subprocess.run([sys.executable, "-m", "whisklet.selftest"], cwd=args.sdk_root / "sdk" / "python", capture_output=True, encoding="utf-8")
    (args.output / "offline.txt").write_text(offline.stdout + offline.stderr, encoding="utf-8")
    print("offline exit=" + str(offline.returncode), flush=True)
    for method in ("app_config", "advert", "nav", "top_notice", "notice", "index_recommend", "last_version"):
        call(method, {"token": ""})
    listing = call("video_list", {"tid": 2, "pg": 1, "limit": 10})
    call("search", {"text": "妻", "pg": 1, "token": ""})
    call("rank_list", {})
    call("notice_detail", {})
    advert = decoded.get("advert", {}).get("data", {})
    advert_id = (advert.get("advert_app_id") or {}).get("id", 93) if isinstance(advert, dict) else 93
    call("advert_detail", {"id": advert_id})
    items = listing.get("data") or []
    vod_id = items[0].get("vod_id") if isinstance(items, list) and items else 597546
    detail = call("video_detail", {"id": vod_id})
    call("comment_list", {"vid": vod_id, "token": ""})
    call("dm_list", {"group_key": hashlib.md5(str(vod_id).encode()).hexdigest()[:20], "token": ""})
    call("vod_heat_add", {"id": vod_id, "token": ""})
    sources = ((detail.get("data") or {}).get("vod_info") or {}).get("vod_url_with_player") or []
    platform = next((source for source in sources if "/ajiami/" in (source.get("parse_api") or "")), None)
    if not platform and isinstance(items, list):
        for candidate in items[1:7]:
            candidate_detail = call("video_detail", {"id": candidate["vod_id"]}, "detail_candidate_" + str(candidate["vod_id"]))
            candidate_sources = ((candidate_detail.get("data") or {}).get("vod_info") or {}).get("vod_url_with_player") or []
            platform = next((source for source in candidate_sources if "/ajiami/" in (source.get("parse_api") or "")), None)
            if platform:
                sources = candidate_sources
                break
    if platform:
        token = platform["url"].split("#")[0].partition("$")[2]
        param = call("secret_parse_api_url", {"url": token, "player_code": platform["code"], "token": ""})
        expected = {"BBA": 800, "co": 88, "NBY": 288, "zijianm3u8": 172, "rose": 232, "youku": 144, "qq": 144}.get(platform["code"])
        for attempt in range(1, 8):
            if isinstance(param.get("data"), str) and len(param["data"]) == expected:
                break
            param = call("secret_parse_api_url", {"url": token, "player_code": platform["code"], "token": ""}, "parse_retry_" + str(attempt))
        if isinstance(param.get("data"), str) and len(param["data"]) == expected:
            parser_url = platform["parse_api"].split("?url=")[0] + "?url=" + urllib.parse.quote(param["data"], safe="")
            parsed = get(parser_url, "platform_parser")
            try:
                media_url = json.loads(parsed).get("url")
                if media_url:
                    get(media_url, "platform_media", limit=64, media=True)
            except (ValueError, TypeError):
                pass
    else:
        call("secret_parse_api_url", {"url": "", "player_code": "BBA", "token": ""})
    for source in sources:
        token = (source.get("url") or "").split("#")[0].partition("$")[2]
        if not token:
            continue
        if source.get("parse_api"):
            if "/ajiami/" not in source["parse_api"]:
                get(source["parse_api"] + token, "external_" + str(source.get("code")))
            continue
        label = "hls_" + str(source.get("code"))
        manifest = get(token, label)
        if manifest.startswith("#EXTM3U"):
            children = [line.strip() for line in manifest.splitlines() if line.strip() and not line.startswith("#")]
            if children:
                child = urllib.parse.urljoin(token, children[0])
                if ".m3u8" in child:
                    nested = get(child, label + "_variant")
                    segments = [line.strip() for line in nested.splitlines() if line.strip() and not line.startswith("#")]
                    if nested.startswith("#EXTM3U") and segments:
                        get(urllib.parse.urljoin(child, segments[0]), label + "_segment", limit=64, media=True)
                else:
                    get(child, label + "_segment", limit=64, media=True)
    call("video_list", {"tid": 2, "pg": 2, "limit": 10}, "video_list_page2")
    call("video_list", {"tid": 20, "pg": 1, "limit": 5}, "video_list_live")
    print("Evidence: " + str(args.output.resolve()), flush=True)


if __name__ == "__main__":
    main()
