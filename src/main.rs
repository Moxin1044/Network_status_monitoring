use std::collections::HashMap;
use std::path::Path;
use std::time::Duration;

use chrono::Local;
use if_addrs::get_if_addrs;
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
struct Config {
    feishu_webhook: String,
    check_interval: Option<u64>,
}

async fn load_config() -> Config {
    let paths = [
        "config.yml",
        "/etc/network_status_monitoring/config.yml",
        "C:\\Program Files\\NetworkStatusMonitoring\\config.yml",
    ];
    for p in &paths {
        if Path::new(p).exists() {
            let content = tokio::fs::read_to_string(p).await.unwrap_or_default();
            if let Ok(cfg) = serde_yaml::from_str::<Config>(&content) {
                println!("[{}] 已加载配置文件: {}", ts(), p);
                return cfg;
            }
        }
    }
    let default = Config {
        feishu_webhook: "*".to_string(),
        check_interval: Some(30),
    };
    println!("[{}] 未找到配置文件，使用默认配置", ts());
    default
}

fn ts() -> String {
    Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

fn is_monitored_iface(name: &str) -> bool {
    name.starts_with("ens") || name.starts_with("enp") || name.starts_with("wlp")
}

fn iface_icon(name: &str) -> &'static str {
    if name.starts_with("wlp") { "\u{1F4F6}" } else { "\u{1F5A7}" }
}

fn get_internal_ips() -> HashMap<String, Vec<String>> {
    let ifaces = match get_if_addrs() {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[{}] 获取网络接口失败: {}", ts(), e);
            return HashMap::new();
        }
    };
    let mut map: HashMap<String, Vec<String>> = HashMap::new();
    for iface in ifaces {
        if is_monitored_iface(&iface.name) {
            map.entry(iface.name.clone())
                .or_default()
                .push(iface.addr.ip().to_string());
        }
    }
    for v in map.values_mut() {
        v.sort();
    }
    map
}

async fn get_public_ip(client: &Client) -> Option<String> {
    let urls = [
        "https://api.ipify.org",
        "https://checkip.amazonaws.com",
        "https://icanhazip.com",
        "https://ifconfig.me/ip",
    ];
    for url in &urls {
        match client.get(*url).timeout(Duration::from_secs(10)).send().await {
            Ok(resp) => {
                if let Ok(text) = resp.text().await {
                    let ip = text.trim().to_string();
                    if ip.parse::<std::net::IpAddr>().is_ok() {
                        return Some(ip);
                    }
                }
            }
            Err(e) => {
                eprintln!("[{}] 请求 {} 失败: {}", ts(), url, e);
            }
        }
    }
    None
}

#[derive(Clone)]
enum IfaceChange {
    Modified { name: String, old_ips: Vec<String>, new_ips: Vec<String> },
    Up { name: String, ips: Vec<String> },
    Down { name: String },
}

#[derive(Clone)]
enum PublicChange {
    Changed { old: String, new: String },
    Lost { old: String },
    Restored { new: String },
}

fn diff_internal(
    old: &HashMap<String, Vec<String>>,
    new: &HashMap<String, Vec<String>>,
) -> Vec<IfaceChange> {
    let mut changes = Vec::new();
    for (name, ips) in new {
        match old.get(name) {
            Some(old_ips) if old_ips != ips => {
                changes.push(IfaceChange::Modified {
                    name: name.clone(),
                    old_ips: old_ips.clone(),
                    new_ips: ips.clone(),
                });
            }
            Some(_) => {}
            None => {
                changes.push(IfaceChange::Up { name: name.clone(), ips: ips.clone() });
            }
        }
    }
    let mut down_names: Vec<&String> = old.keys().filter(|n| !new.contains_key(*n)).collect();
    down_names.sort();
    for name in down_names {
        changes.push(IfaceChange::Down { name: name.clone() });
    }
    changes
}

fn detect_public_change(old: &Option<String>, new: &Option<String>) -> Option<PublicChange> {
    match (old, new) {
        (Some(prev), Some(cur)) if prev != cur => Some(PublicChange::Changed {
            old: prev.clone(),
            new: cur.clone(),
        }),
        (Some(prev), None) => Some(PublicChange::Lost { old: prev.clone() }),
        (None, Some(cur)) => Some(PublicChange::Restored { new: cur.clone() }),
        _ => None,
    }
}

fn print_banner() {
    println!();
    println!("  \u{258C} Network Status Monitor v0.1");
    println!("  \u{258C} \u{1F4E1} 接口: ens* / enp* / wlp*");
    println!("  \u{258C} \u{1F310} 公网: 直连检测 (不走代理)");
    println!();
}

fn print_snapshot(internal: &HashMap<String, Vec<String>>, public: &Option<String>) {
    println!("\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}");
    println!("\u{2502} \u{1F4CB} 网络状态快照  {}", ts());
    println!("\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}");
    if internal.is_empty() {
        println!("\u{2502} \u{26A0}\u{FE0F}  未检测到监控网络接口");
    } else {
        let mut names: Vec<&String> = internal.keys().collect();
        names.sort();
        for name in &names {
            let icon = iface_icon(name);
            println!("\u{2502} {} {}  {}", icon, name, internal[*name].join(", "));
        }
    }
    println!("\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}");
    match public {
        Some(ip) => println!("\u{2502} \u{1F310} 公网 IP  {}", ip),
        None => println!("\u{2502} \u{1F310} 公网 IP  无法获取"),
    }
    println!("\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}");
    println!();
}

fn print_changes(iface_changes: &[IfaceChange], public_change: &Option<PublicChange>) {
    println!("\u{250C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2510}");
    println!("\u{2502} \u{26A1} 网络状态变更  {}", ts());
    println!("\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}");
    for c in iface_changes {
        match c {
            IfaceChange::Modified { name, old_ips, new_ips } => {
                let icon = iface_icon(name);
                println!("\u{2502} {} {} IP变更", icon, name);
                println!("\u{2502}    \u{21A9}\u{FE0F} {}", old_ips.join(", "));
                println!("\u{2502}    \u{27A1}\u{FE0F} {}", new_ips.join(", "));
            }
            IfaceChange::Up { name, ips } => {
                let icon = iface_icon(name);
                println!("\u{2502} \u{2705} {} {} 上线  [{}]", icon, name, ips.join(", "));
            }
            IfaceChange::Down { name } => {
                println!("\u{2502} \u{274C} {} 下线", name);
            }
        }
    }
    if let Some(pc) = public_change {
        println!("\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}");
        match pc {
            PublicChange::Changed { old, new } => {
                println!("\u{2502} \u{1F310} 公网 IP 变更");
                println!("\u{2502}    \u{21A9}\u{FE0F} {}", old);
                println!("\u{2502}    \u{27A1}\u{FE0F} {}", new);
            }
            PublicChange::Lost { old } => {
                println!("\u{2502} \u{274C} 公网 IP 丢失 (原: {})", old);
            }
            PublicChange::Restored { new } => {
                println!("\u{2502} \u{2705} 公网 IP 恢复: {}", new);
            }
        }
    }
    println!("\u{2514}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2518}");
    println!();
}

#[derive(Serialize)]
#[serde(untagged)]
enum CardElement {
    Markdown {
        tag: String,
        content: String,
        text_align: String,
        text_size: String,
        margin: String,
    },
    Hr {
        tag: String,
    },
}

#[derive(Serialize)]
struct FeishuCard {
    msg_type: String,
    card: FeishuCardBody,
}

#[derive(Serialize)]
struct FeishuCardBody {
    schema: String,
    config: FeishuCardConfig,
    header: FeishuCardHeader,
    body: FeishuCardBodyContent,
}

#[derive(Serialize)]
struct FeishuCardConfig {
    update_multi: bool,
}

#[derive(Serialize)]
struct FeishuCardHeader {
    title: FeishuCardTitle,
    template: String,
}

#[derive(Serialize)]
struct FeishuCardTitle {
    tag: String,
    content: String,
}

#[derive(Serialize)]
struct FeishuCardBodyContent {
    direction: String,
    padding: String,
    elements: Vec<CardElement>,
}

fn md(content: &str, margin: &str) -> CardElement {
    CardElement::Markdown {
        tag: "markdown".to_string(),
        content: content.to_string(),
        text_align: "left".to_string(),
        text_size: "normal_v2".to_string(),
        margin: margin.to_string(),
    }
}

fn hr() -> CardElement {
    CardElement::Hr { tag: "hr".to_string() }
}

fn build_change_card(iface_changes: &[IfaceChange], public_change: &Option<PublicChange>) -> FeishuCard {
    let has_severe = iface_changes.iter().any(|c| matches!(c, IfaceChange::Down { .. }))
        || public_change.as_ref().map_or(false, |pc| matches!(pc, PublicChange::Lost { .. }));
    let template = if has_severe { "red" } else { "orange" };

    let mut elements: Vec<CardElement> = Vec::new();

    let mut summary: Vec<String> = Vec::new();
    for c in iface_changes {
        match c {
            IfaceChange::Modified { name, .. } => summary.push(format!("`{}` IP变更", name)),
            IfaceChange::Up { name, .. } => summary.push(format!("`{}` 上线", name)),
            IfaceChange::Down { name } => summary.push(format!("`{}` 下线", name)),
        }
    }
    match public_change {
        Some(PublicChange::Changed { .. }) => summary.push("公网IP变更".to_string()),
        Some(PublicChange::Lost { .. }) => summary.push("公网IP丢失".to_string()),
        Some(PublicChange::Restored { .. }) => summary.push("公网IP恢复".to_string()),
        None => {}
    }
    elements.push(md(&format!("📡 **检测到变更**: {}", summary.join("、")), "0px 0px 8px 0px"));
    elements.push(hr());

    for c in iface_changes {
        match c {
            IfaceChange::Modified { name, old_ips, new_ips } => {
                let icon = iface_icon(name);
                elements.push(md(
                    &format!(
                        "{} **{}** IP变更\n\u{21A9}\u{FE0F} 旧: `{}`\n\u{27A1}\u{FE0F} 新: `{}`",
                        icon, name,
                        old_ips.join("`, `"),
                        new_ips.join("`, `"),
                    ),
                    "8px 0px 4px 0px",
                ));
            }
            IfaceChange::Up { name, ips } => {
                let icon = iface_icon(name);
                elements.push(md(
                    &format!("✅ {} **{}** 上线\nIP: `{}`", icon, name, ips.join("`, `")),
                    "8px 0px 4px 0px",
                ));
            }
            IfaceChange::Down { name } => {
                elements.push(md(&format!("❌ **{}** 下线", name), "8px 0px 4px 0px"));
            }
        }
    }

    if let Some(pc) = public_change {
        elements.push(hr());
        match pc {
            PublicChange::Changed { old, new } => {
                elements.push(md(
                    &format!("🌐 **公网IP变更**\n\u{21A9}\u{FE0F} 旧: `{}`\n\u{27A1}\u{FE0F} 新: `{}`", old, new),
                    "8px 0px 4px 0px",
                ));
            }
            PublicChange::Lost { old } => {
                elements.push(md(&format!("❌ **公网IP丢失** (原: `{}`)", old), "8px 0px 4px 0px"));
            }
            PublicChange::Restored { new } => {
                elements.push(md(&format!("✅ **公网IP恢复**: `{}`", new), "8px 0px 4px 0px"));
            }
        }
    }

    elements.push(hr());
    elements.push(md(&format!("🕐 {}", ts()), "4px 0px 0px 0px"));

    FeishuCard {
        msg_type: "interactive".to_string(),
        card: FeishuCardBody {
            schema: "2.0".to_string(),
            config: FeishuCardConfig { update_multi: true },
            header: FeishuCardHeader {
                title: FeishuCardTitle {
                    tag: "plain_text".to_string(),
                    content: "⚠️ 网络状态变更通知".to_string(),
                },
                template: template.to_string(),
            },
            body: FeishuCardBodyContent {
                direction: "vertical".to_string(),
                padding: "12px 12px 12px 12px".to_string(),
                elements,
            },
        },
    }
}

fn build_init_card(internal: &HashMap<String, Vec<String>>, public: &Option<String>) -> FeishuCard {
    let mut elements: Vec<CardElement> = Vec::new();

    let mut names: Vec<&String> = internal.keys().collect();
    names.sort();

    elements.push(md("📡 **监控已启动，当前网络状态如下**", "0px 0px 8px 0px"));
    elements.push(hr());

    if names.is_empty() {
        elements.push(md("⚠️ 未检测到监控网络接口", "8px 0px 4px 0px"));
    } else {
        for name in &names {
            let icon = iface_icon(name);
            elements.push(md(
                &format!("{} **{}**\nIP: `{}`", icon, name, internal[*name].join("`, `")),
                "8px 0px 4px 0px",
            ));
        }
    }

    elements.push(hr());
    match public {
        Some(ip) => elements.push(md(&format!("🌐 **公网 IP**: `{}`", ip), "8px 0px 4px 0px")),
        None => elements.push(md("🌐 **公网 IP**: 无法获取", "8px 0px 4px 0px")),
    }

    elements.push(hr());
    elements.push(md(&format!("🕐 {}", ts()), "4px 0px 0px 0px"));

    FeishuCard {
        msg_type: "interactive".to_string(),
        card: FeishuCardBody {
            schema: "2.0".to_string(),
            config: FeishuCardConfig { update_multi: true },
            header: FeishuCardHeader {
                title: FeishuCardTitle {
                    tag: "plain_text".to_string(),
                    content: "🟢 网络监控启动".to_string(),
                },
                template: "blue".to_string(),
            },
            body: FeishuCardBodyContent {
                direction: "vertical".to_string(),
                padding: "12px 12px 12px 12px".to_string(),
                elements,
            },
        },
    }
}

async fn send_feishu(client: &Client, webhook: &str, card: &FeishuCard) {
    let body = serde_json::to_string(card).unwrap_or_default();
    match client
        .post(webhook)
        .header("Content-Type", "application/json")
        .body(body)
        .timeout(Duration::from_secs(10))
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            if status.is_success() {
                println!("[{}] 📨 飞书通知已发送", ts());
            } else {
                let text = resp.text().await.unwrap_or_default();
                eprintln!("[{}] 飞书通知发送失败: {} {}", ts(), status, text);
            }
        }
        Err(e) => {
            eprintln!("[{}] 飞书通知发送失败: {}", ts(), e);
        }
    }
}

#[tokio::main]
async fn main() {
    let config = load_config().await;
    let interval_secs = config.check_interval.unwrap_or(30);

    print_banner();
    println!("[{}] 监控启动，检测间隔 {} 秒", ts(), interval_secs);
    let masked = if config.feishu_webhook.len() > 58 {
        format!("{}...{}", &config.feishu_webhook[..42], &config.feishu_webhook[config.feishu_webhook.len() - 8..])
    } else {
        config.feishu_webhook.clone()
    };
    println!("[{}] 飞书 Webhook: {}", ts(), masked);

    let client = Client::builder()
        .no_proxy()
        .user_agent("NetworkStatusMonitor/0.1")
        .timeout(Duration::from_secs(15))
        .build()
        .expect("无法创建 HTTP 客户端");

    let mut prev_internal: HashMap<String, Vec<String>> = HashMap::new();
    let mut prev_public: Option<String> = None;
    let mut initialized = false;

    loop {
        let current_internal = get_internal_ips();
        let current_public = get_public_ip(&client).await;

        if !initialized {
            print_snapshot(&current_internal, &current_public);
            let card = build_init_card(&current_internal, &current_public);
            send_feishu(&client, &config.feishu_webhook, &card).await;
            prev_internal = current_internal;
            prev_public = current_public;
            initialized = true;
        } else {
            let iface_changes = if prev_internal != current_internal {
                diff_internal(&prev_internal, &current_internal)
            } else {
                Vec::new()
            };
            let public_change = detect_public_change(&prev_public, &current_public);

            let has_change = !iface_changes.is_empty() || public_change.is_some();

            if has_change {
                print_changes(&iface_changes, &public_change);
                let card = build_change_card(&iface_changes, &public_change);
                send_feishu(&client, &config.feishu_webhook, &card).await;
            }

            prev_internal = current_internal;
            prev_public = current_public;
        }

        tokio::select! {
            _ = tokio::time::sleep(Duration::from_secs(interval_secs)) => {}
            _ = tokio::signal::ctrl_c() => {
                println!("\n[{}] 监控已停止", ts());
                break;
            }
        }
    }
}
