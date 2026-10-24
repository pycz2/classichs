//! How a bot talks to a game server: one interface (the protocol's JSON messages, `send` / `next`),
//! two adapters. **Local**: inside this server process, through in-memory channels into the same
//! session code a WebSocket client gets (`ws::serve`) — no sockets, no TLS, the same answers, so the bot
//! sees only its own player's view. **Net**: a WebSocket to any server (`ws://` or `wss://`).

use crate::AppRef;
use axum::extract::ws::Message as AxMsg;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use std::net::{IpAddr, Ipv4Addr};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::timeout;
use tokio_tungstenite::tungstenite::Message as WsMsg;

pub enum Transport {
    Local(Local),
    Net(Box<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>>),
}

pub struct Local {
    to_server: mpsc::UnboundedSender<Result<AxMsg, String>>,
    from_server: mpsc::Receiver<AxMsg>,
}

impl Transport {
    /// A client of this very server process (its session runs on the server's tasks).
    pub fn local(app: &AppRef) -> Transport {
        let (to_server, rx) = mpsc::unbounded_channel::<Result<AxMsg, String>>();
        let (tx, from_server) = mpsc::channel::<AxMsg>(1024);
        let stream = Box::pin(futures_util::stream::unfold(rx, |mut rx| async move { rx.recv().await.map(|m| (m, rx)) }));
        let sink = tokio_util::sync::PollSender::new(tx);
        tokio::spawn(crate::ws::serve(app.clone(), sink, stream, IpAddr::V4(Ipv4Addr::LOCALHOST), true));
        Transport::Local(Local { to_server, from_server })
    }

    /// A client of a server over the network.
    pub async fn net(url: &str) -> Result<Transport, String> {
        let (ws, _) = tokio_tungstenite::connect_async(url).await.map_err(|e| format!("connect {url}: {e}"))?;
        Ok(Transport::Net(Box::new(ws)))
    }

    pub async fn send(&mut self, v: Value) -> Result<(), String> {
        match self {
            Transport::Local(l) => l.to_server.send(Ok(AxMsg::Text(v.to_string().into()))).map_err(|_| "the server closed the session".into()),
            Transport::Net(ws) => ws.send(WsMsg::text(v.to_string())).await.map_err(|e| format!("send: {e}")),
        }
    }

    /// The next JSON message (None: nothing within `wait`); Err when the connection is gone.
    pub async fn next(&mut self, wait: Duration) -> Result<Option<Value>, String> {
        match self {
            Transport::Local(l) => match timeout(wait, l.from_server.recv()).await {
                Err(_) => Ok(None),
                Ok(None) => Err("the server closed the session".into()),
                Ok(Some(AxMsg::Text(t))) => Ok(serde_json::from_str(t.as_str()).ok()),
                Ok(Some(AxMsg::Close(c))) => Err(format!("closed by the server: {}", c.map_or(String::new(), |c| c.reason.to_string()))),
                Ok(Some(_)) => Ok(None),
            },
            Transport::Net(ws) => match timeout(wait, ws.next()).await {
                Err(_) => Ok(None),
                Ok(None) => Err("the server closed the connection".into()),
                Ok(Some(Err(e))) => Err(format!("connection: {e}")),
                Ok(Some(Ok(WsMsg::Text(t)))) => Ok(serde_json::from_str(t.as_str()).ok()),
                Ok(Some(Ok(WsMsg::Close(c)))) => Err(format!("closed by the server: {}", c.map_or(String::new(), |c| c.reason.to_string()))),
                Ok(Some(Ok(_))) => Ok(None),
            },
        }
    }
}
