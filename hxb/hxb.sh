#!/bin/bash
# 欢喜币(HXB)命令行工具
# 用法: ./hxb.sh [命令] [参数]

HXB_DIR="/Users/huanxi/.openclaw/workspace-main/hxb"

case "$1" in
  balance|bal)
    # 查看余额: ./hxb.sh balance 蕊蕊
    if [ -f "$HXB_DIR/wallets/$2.json" ]; then
      balance=$(cat "$HXB_DIR/wallets/$2.json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'{d[\"agent_name\"]} | 等级:{d[\"level\"]} | 余额:{d[\"balance\"]} HXB | 总收入:{d[\"total_earned\"]} | 总支出:{d[\"total_spent\"]}')")
      echo "$balance"
    else
      echo "找不到钱包: $2"
      echo "可用钱包: 太阳 蕊蕊 开心果 光头强 梦梦 灵夕 跳跳 朵朵"
    fi
    ;;
    
  all)
    # 查看所有人余额
    echo "====== 欢喜币(HXB)余额总览 ======"
    for f in "$HXB_DIR/wallets/"*.json; do
      name=$(basename "$f" .json)
      balance=$(cat "$f" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'{d[\"agent_name\"]}({d[\"level\"]}): {d[\"balance\"]} HXB')")
      echo "  $balance"
    done
    echo "=================================="
    ;;
    
  reward|pay)
    # 发放奖励: ./hxb.sh reward 蕊蕊 200 "完成日报任务"
    if [ -f "$HXB_DIR/wallets/$2.json" ]; then
      python3 << PYTHON
import json, datetime

wallet_file = "$HXB_DIR/wallets/$2.json"
amount = int("$3")
reason = "$4"
tx_file = "$HXB_DIR/transactions.json"

# 更新钱包
with open(wallet_file, 'r') as f:
    wallet = json.load(f)

wallet['balance'] += amount
wallet['total_earned'] += amount
wallet['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')

tx = {
    'type': 'reward',
    'amount': amount,
    'reason': reason,
    'from': '系统',
    'to': wallet['agent_name'],
    'time': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
    'balance_after': wallet['balance']
}
wallet['transactions'].append(tx)

with open(wallet_file, 'w') as f:
    json.dump(wallet, f, ensure_ascii=False, indent=2)

# 更新全局流水
with open(tx_file, 'r') as f:
    transactions = json.load(f)
transactions['records'].append(tx)
with open(tx_file, 'w') as f:
    json.dump(transactions, f, ensure_ascii=False, indent=2)

print(f"✅ 已向 {wallet['agent_name']} 发放 {amount} HXB | 原因: {reason} | 当前余额: {wallet['balance']} HXB")
PYTHON
    else
      echo "找不到钱包: $2"
    fi
    ;;
    
  deduct|freeze)
    # 扣款: ./hxb.sh deduct 蕊蕊 100 "任务不合格"
    if [ -f "$HXB_DIR/wallets/$2.json" ]; then
      python3 << PYTHON
import json, datetime

wallet_file = "$HXB_DIR/wallets/$2.json"
amount = int("$3")
reason = "$4"
tx_file = "$HXB_DIR/transactions.json"

with open(wallet_file, 'r') as f:
    wallet = json.load(f)

if wallet['balance'] < amount:
    print(f"⚠️ 余额不足! {wallet['agent_name']} 当前余额 {wallet['balance']} HXB，需扣 {amount} HXB")
else:
    wallet['balance'] -= amount
    wallet['total_spent'] += amount
    wallet['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
    
    tx = {
        'type': 'deduct',
        'amount': -amount,
        'reason': reason,
        'from': wallet['agent_name'],
        'to': '系统',
        'time': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
        'balance_after': wallet['balance']
    }
    wallet['transactions'].append(tx)
    
    with open(wallet_file, 'w') as f:
        json.dump(wallet, f, ensure_ascii=False, indent=2)
    
    with open(tx_file, 'r') as f:
        transactions = json.load(f)
    transactions['records'].append(tx)
    with open(tx_file, 'w') as f:
        json.dump(transactions, f, ensure_ascii=False, indent=2)
    
    print(f"✅ 已从 {wallet['agent_name']} 扣除 {amount} HXB | 原因: {reason} | 当前余额: {wallet['balance']} HXB")
PYTHON
    else
      echo "找不到钱包: $2"
    fi
    ;;
    
  log|history)
    # 查看交易记录: ./hxb.sh log 蕊蕊
    if [ -f "$HXB_DIR/wallets/$2.json" ]; then
      python3 << PYTHON
import json

with open("$HXB_DIR/wallets/$2.json", 'r') as f:
    wallet = json.load(f)

print(f"====== {wallet['agent_name']} 交易记录 ======")
for tx in wallet['transactions'][-10:]:  # 最近10条
    sign = "+" if tx['amount'] > 0 else ""
    print(f"  [{tx['time']}] {sign}{tx['amount']} HXB | {tx['reason']} | 余额:{tx['balance_after']}")
if not wallet['transactions']:
    print("  暂无交易记录")
PYTHON
    fi
    ;;
    
  transfer)
    # 转账: ./hxb.sh transfer 太阳 蕊蕊 500 "任务奖励"
    python3 << PYTHON
import json, datetime

from_wallet = "$HXB_DIR/wallets/$2.json"
to_wallet = "$HXB_DIR/wallets/$3.json"
amount = int("$4")
reason = "$5"
tx_file = "$HXB_DIR/transactions.json"

with open(from_wallet, 'r') as f:
    sender = json.load(f)
with open(to_wallet, 'r') as f:
    receiver = json.load(f)

if sender['balance'] < amount:
    print(f"⚠️ 余额不足! {sender['agent_name']} 当前余额 {sender['balance']} HXB")
else:
    sender['balance'] -= amount
    sender['total_spent'] += amount
    receiver['balance'] += amount
    receiver['total_earned'] += amount
    
    tx = {
        'type': 'transfer',
        'amount': amount,
        'reason': reason,
        'from': sender['agent_name'],
        'to': receiver['agent_name'],
        'time': datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
        'from_balance': sender['balance'],
        'to_balance': receiver['balance']
    }
    sender['transactions'].append(tx)
    receiver['transactions'].append(tx)
    
    with open(from_wallet, 'w') as f:
        json.dump(sender, f, ensure_ascii=False, indent=2)
    with open(to_wallet, 'w') as f:
        json.dump(receiver, f, ensure_ascii=False, indent=2)
    
    with open(tx_file, 'r') as f:
        transactions = json.load(f)
    transactions['records'].append(tx)
    with open(tx_file, 'w') as f:
        json.dump(transactions, f, ensure_ascii=False, indent=2)
    
    print(f"✅ {sender['agent_name']} → {receiver['agent_name']} {amount} HXB | {reason}")
    print(f"   {sender['agent_name']}: {sender['balance']} HXB | {receiver['agent_name']}: {receiver['balance']} HXB")
PYTHON
    ;;
    
  *)
    echo "🪙 欢喜币(HXB)命令行工具"
    echo ""
    echo "用法:"
    echo "  ./hxb.sh all                    查看所有人余额"
    echo "  ./hxb.sh balance [花名]         查看单人余额"
    echo "  ./hxb.sh reward [花名] [金额] [原因]   发放奖励"
    echo "  ./hxb.sh deduct [花名] [金额] [原因]   扣款"
    echo "  ./hxb.sh transfer [转出] [转入] [金额] [原因]  转账"
    echo "  ./hxb.sh log [花名]             查看交易记录"
    echo ""
    echo "示例:"
    echo "  ./hxb.sh reward 蕊蕊 200 完成日报任务"
    echo "  ./hxb.sh deduct 跳跳 50 任务超时"
    echo "  ./hxb.sh transfer 太阳 梦梦 300 周奖"
    ;;
esac
