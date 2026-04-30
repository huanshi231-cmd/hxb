#!/usr/bin/env python3
"""
HXB结算脚本 - 太阳调用，自动完成评分/记账/飞书通知
用法：python3 hxb_settle.py settle <task_id> <agent> <score_完整性> <score_时效性> <score_质量度>
      python3 hxb_settle.py leaderboard
      python3 hxb_settle.py balance <agent>
      python3 hxb_settle.py new_task <title> <agent> <reward> <level>
"""

import json
import sys
import os
import subprocess
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
WALLETS_DIR = os.path.join(BASE, "wallets")
TASKS_FILE = os.path.join(BASE, "tasks.json")
TX_FILE = os.path.join(BASE, "transactions.json")
CONFIG_FILE = os.path.join(BASE, "config.json")

FEISHU_GROUP = "oc_6c409c73f6d1bc540d0e54d472ea6bf2"

AGENT_MAP = {
    "太阳": "taiyang", "蕊蕊": "ruirui", "开心果": "kaixin",
    "光头强": "guangtouqiang", "梦梦": "mengmeng",
    "灵夕": "lingxi", "跳跳": "tiaotiao", "朵朵": "duoduo"
}


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_wallet(agent_name):
    path = os.path.join(WALLETS_DIR, f"{agent_name}.json")
    return load_json(path), path


def now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def calc_score(s_complete, s_time, s_quality):
    return round(s_complete * 0.4 + s_time * 0.3 + s_quality * 0.3)


def calc_coefficient(score):
    cfg = load_json(CONFIG_FILE)["quality_coefficients"]
    for k, v in cfg.items():
        if score >= v["min_score"]:
            return v["coefficient"], v["label"]
    return 0, "不合格"


def send_feishu(msg):
    """通过OpenClaw message工具发飞书消息"""
    cmd = f'openclaw message send --channel feishu --account main --target {FEISHU_GROUP} --message "{msg}"'
    os.system(cmd)


def cmd_new_task(title, agent, reward, level):
    tasks = load_json(TASKS_FILE)
    task_id = f"T{len(tasks['tasks'])+1:04d}"
    task = {
        "id": task_id,
        "title": title,
        "assigned_to": agent,
        "reward": int(reward),
        "level": level,
        "status": "进行中",
        "created_at": now(),
        "deadline": None,
        "submitted_at": None,
        "score": None,
        "settled_at": None
    }
    tasks["tasks"].append(task)
    save_json(TASKS_FILE, tasks)
    print(f"✅ 任务已创建：{task_id} - {title}，分配给{agent}，奖励{reward} HXB")
    send_feishu(f"【HXB新任务】{task_id}\n任务：{title}\n接单人：{agent}\n奖励：{reward} HXB\n等级：{level}")


def cmd_settle(task_id, agent, s1, s2, s3):
    s1, s2, s3 = int(s1), int(s2), int(s3)
    score = calc_score(s1, s2, s3)
    coef, label = calc_coefficient(score)

    tasks = load_json(TASKS_FILE)
    task = next((t for t in tasks["tasks"] if t["id"] == task_id), None)
    if not task:
        print(f"❌ 找不到任务 {task_id}")
        sys.exit(1)

    reward_base = task["reward"]
    reward_final = round(reward_base * coef)

    # 更新任务状态
    task["status"] = "已结算"
    task["submitted_at"] = task.get("submitted_at") or now()
    task["score"] = {"完整性": s1, "时效性": s2, "质量度": s3, "总分": score, "评级": label}
    task["settled_at"] = now()
    task["reward_final"] = reward_final
    save_json(TASKS_FILE, tasks)

    # 更新钱包
    wallet, wpath = load_wallet(agent)
    wallet["balance"] += reward_final
    wallet["total_earned"] += reward_final
    wallet["updated_at"] = now()
    tx = {
        "id": f"TX{datetime.now().strftime('%Y%m%d%H%M%S')}",
        "type": "任务奖励",
        "task_id": task_id,
        "amount": reward_final,
        "score": score,
        "label": label,
        "timestamp": now()
    }
    wallet["transactions"].append(tx)
    save_json(wpath, wallet)

    # 写全局流水
    txs = load_json(TX_FILE) if os.path.exists(TX_FILE) else {"transactions": []}
    txs["transactions"].append({**tx, "agent": agent})
    save_json(TX_FILE, txs)

    result = (
        f"【HXB结算】{task_id}\n"
        f"任务：{task['title']}\n"
        f"执行人：{agent}\n"
        f"评分：完整性{s1} / 时效性{s2} / 质量{s3} → 总分{score}（{label}）\n"
        f"奖励：{reward_base} × {coef} = {reward_final} HXB\n"
        f"当前余额：{wallet['balance']} HXB"
    )
    print(result)
    send_feishu(result)


def cmd_leaderboard():
    rows = []
    for name in AGENT_MAP:
        wpath = os.path.join(WALLETS_DIR, f"{name}.json")
        if os.path.exists(wpath):
            w = load_json(wpath)
            rows.append((name, w["balance"], w["level"]))
    rows.sort(key=lambda x: -x[1])

    lines = ["【HXB每日排行榜】" + datetime.now().strftime("%m-%d"), ""]
    medals = ["🥇", "🥈", "🥉"]
    for i, (name, bal, lv) in enumerate(rows):
        m = medals[i] if i < 3 else f"{i+1}."
        lines.append(f"{m} {name}（{lv}级）— {bal} HXB")
    msg = "\n".join(lines)
    print(msg)
    send_feishu(msg)


def cmd_balance(agent):
    wallet, _ = load_wallet(agent)
    print(f"{agent} 当前余额：{wallet['balance']} HXB（{wallet['level']}级）")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    if cmd == "settle" and len(args) == 5:
        cmd_settle(*args)
    elif cmd == "leaderboard":
        cmd_leaderboard()
    elif cmd == "balance" and len(args) == 1:
        cmd_balance(args[0])
    elif cmd == "new_task" and len(args) == 4:
        cmd_new_task(*args)
    else:
        print(__doc__)
