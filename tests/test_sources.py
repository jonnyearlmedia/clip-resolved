from clip_resolved.sources import infer_source_label, load_sources, register_source, source_for_path


def test_project_sources_persist_incrementally_and_match_nested_media(tmp_path):
    project = tmp_path / "Project"
    osmo = tmp_path / "cards" / "osmo"
    phone = tmp_path / "later" / "phone"
    osmo.mkdir(parents=True)
    phone.mkdir(parents=True)
    osmo_clip = osmo / "DJI_20260928_0001_D.MP4"
    phone_clip = phone / "IMG_0042.MOV"
    osmo_clip.write_bytes(b"osmo")
    phone_clip.write_bytes(b"phone")

    register_source(project, osmo)
    register_source(project, phone)

    sources = load_sources(project)
    assert [item.label for item in sources] == ["OSMO", "IPHONE"]
    assert source_for_path(project, osmo_clip).label == "OSMO"
    assert source_for_path(project, phone_clip).label == "IPHONE"


def test_insta360_label_is_not_collapsed_into_generic_camera(tmp_path):
    source = tmp_path / "Insta360 GO Ultra"
    source.mkdir()
    assert infer_source_label(source) == "INSTA360 GO ULTRA"
