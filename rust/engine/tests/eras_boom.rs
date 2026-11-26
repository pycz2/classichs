//! packs/eras, the versions of The Boomsday Project's time (25770, 26996, 27358, 27405): each version patch's changes
//! as the engine plays them, against the version before. Needs python3 (skipped without it).

#[macro_use]
#[path = "eras_versions/common.rs"]
mod common;
use common::*;

#[test]
fn patch_27358_nerfs_giggling_inventor_mana_wyrm_and_aviana() {
    let Some(_) = eras() else { return };
    assert_eq!(stats("26996", "BOT_270"), Some((5, 2, 1)));
    assert_eq!(stats("27358", "BOT_270"), Some((7, 2, 1)));
    assert_eq!(stats("26996", "VAN_NEW1_012"), Some((1, 1, 3)));
    assert_eq!(stats("27358", "VAN_NEW1_012"), Some((2, 1, 3)));
    assert_eq!(stats("26996", "AT_045"), Some((9, 5, 5)));
    assert_eq!(stats("27358", "AT_045"), Some((10, 5, 5)));
}
