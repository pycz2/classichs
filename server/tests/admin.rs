//! The admin panel: login, CSRF on POST forms, suspend.

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, Request, StatusCode};
use classichs_server::{admin::esc, auth, db, referee::FakeReferee, router, App};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower::ServiceExt;

async fn call(app: &axum::Router, req: Request<Body>) -> (StatusCode, Vec<String>, String) {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let cookies = res.headers().get_all(header::SET_COOKIE).iter().map(|v| v.to_str().unwrap().to_string()).collect();
    let body = axum::body::to_bytes(res.into_body(), 1 << 20).await.unwrap();
    (status, cookies, String::from_utf8_lossy(&body).into_owned())
}

fn csrf_in(body: &str) -> String {
    let i = body.find("name=csrf value=\"").unwrap() + "name=csrf value=\"".len();
    body[i..].split('"').next().unwrap().to_string()
}

fn cookie_value(set: &[String], name: &str) -> String {
    let c = set.iter().find(|c| c.starts_with(&format!("{name}="))).unwrap();
    assert!(c.contains("HttpOnly") && c.contains("SameSite=Strict"));
    c[name.len() + 1..].split(';').next().unwrap().to_string()
}

fn post(uri: &str, cookie: &str, form: &str) -> Request<Body> {
    Request::post(uri)
        .header(header::COOKIE, cookie)
        .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(Body::from(form.to_string()))
        .unwrap()
}

#[tokio::test]
async fn admin_login_and_csrf() {
    let state = App::new(db::Db::open(":memory:").unwrap(), Arc::new(FakeReferee::default()), false, Duration::from_secs(30));
    let hash = auth::hash_password("rootpassword");
    let victim_hash = hash.clone();
    let victim = state
        .db
        .run(move |c| {
            db::make_superuser(c, "root", &hash)?;
            Ok(db::create_account(c, "victim", &victim_hash, "user")?.unwrap())
        })
        .await
        .unwrap();
    let app = router(state.clone()).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 9))));

    // Not logged in: redirected.
    let (s, _, _) = call(&app, Request::get("/admin/accounts").body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::SEE_OTHER);

    // The login form carries a CSRF token matching its cookie.
    let (s, set, body) = call(&app, Request::get("/admin/login").body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::OK);
    let pre = cookie_value(&set, "chs_pre");
    assert_eq!(csrf_in(&body), pre);
    let (s, _, _) = call(&app, post("/admin/login", "", "csrf=x&user=root&password=rootpassword")).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (_, set, body) = call(&app, post("/admin/login", &format!("chs_pre={pre}"), &format!("csrf={pre}&user=root&password=wrongpass"))).await;
    assert!(set.iter().all(|c| !c.starts_with("chs_admin=")) && body.contains("Wrong name or password"));
    let (s, set, _) = call(&app, post("/admin/login", &format!("chs_pre={pre}"), &format!("csrf={pre}&user=root&password=rootpassword"))).await;
    assert_eq!(s, StatusCode::SEE_OTHER);
    let session = format!("chs_admin={}", cookie_value(&set, "chs_admin"));

    // A POST without the CSRF token is refused; with it the account is suspended.
    let uri = format!("/admin/accounts/{victim}/suspend");
    let (s, _, _) = call(&app, post(&uri, &session, "")).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _, _) = call(&app, post(&uri, &session, "csrf=wrong")).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let suspended = |st: classichs_server::AppRef| async move {
        st.db.run(move |c| c.query_row("SELECT suspended FROM accounts WHERE id = ?1", [victim], |r| r.get::<_, i64>(0))).await.unwrap()
    };
    assert_eq!(suspended(state.clone()).await, 0);
    let (s, _, page) = call(&app, Request::get(format!("/admin/accounts/{victim}")).header(header::COOKIE, &session).body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::OK);
    assert!(page.contains("victim"));
    let csrf = csrf_in(&page);
    let (s, _, _) = call(&app, post(&uri, &session, &format!("csrf={csrf}"))).await;
    assert_eq!(s, StatusCode::SEE_OTHER);
    assert_eq!(suspended(state.clone()).await, 1);

    // The superuser cannot be changed from the panel; pages list accounts.
    let (s, _, _) = call(&app, post("/admin/accounts/1/suspend", &session, &format!("csrf={csrf}"))).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _, list) = call(&app, Request::get("/admin/accounts?q=vic").header(header::COOKIE, &session).body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::OK);
    assert!(list.contains("victim") && list.contains("suspended") && !list.contains(">root<"));
    let (s, _, _) = call(&app, Request::get("/admin/games").header(header::COOKIE, &session).body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::OK);

    // Log out: the session is gone.
    let (s, _, _) = call(&app, post("/admin/logout", &session, &format!("csrf={csrf}"))).await;
    assert_eq!(s, StatusCode::SEE_OTHER);
    let (s, _, _) = call(&app, Request::get("/admin/accounts").header(header::COOKIE, &session).body(Body::empty()).unwrap()).await;
    assert_eq!(s, StatusCode::SEE_OTHER);

    assert_eq!(esc("<b a=\"x\">&'"), "&lt;b a=&quot;x&quot;&gt;&amp;&#39;");
}
