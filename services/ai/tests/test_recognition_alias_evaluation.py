from app.training.evaluate_item_recognition import ground_truth_labels


def test_reviewed_mouse_aliases_do_not_accept_other_computer_objects():
    case = {'category': 'Devices', 'subcategory': 'Computers',
            'product_type': 'mouse', 'label': 'mouse'}
    assert ground_truth_labels(case) == {'mouse', 'computer mouse'}
    assert not ground_truth_labels({**case, 'label': 'laptop'})
    assert 'laptop' not in ground_truth_labels(case)


def test_untyped_ground_truth_is_constrained_to_its_actual_object_type():
    case = {'category': 'Devices', 'subcategory': 'Computers', 'label': 'keyboard'}
    assert ground_truth_labels(case) == {'keyboard', 'computer keyboard'}
    assert 'mouse' not in ground_truth_labels(case)
    assert not ground_truth_labels({**case, 'label': 'unknown'})


def test_camera_and_vehicle_aliases_use_reviewed_registry_not_fuzzy_similarity():
    assert 'automobile' in ground_truth_labels({'category': 'Vehicles', 'subcategory': 'Cars', 'label': 'car'})
    camera = {'category': 'Devices', 'subcategory': 'Cameras', 'product_type': 'camera', 'label': 'camera'}
    assert 'digital camera' in ground_truth_labels(camera)
    assert 'camera lens' not in ground_truth_labels(camera)
