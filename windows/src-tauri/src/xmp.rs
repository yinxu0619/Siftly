use crate::model::FileMark;
use quick_xml::{
    events::{BytesStart, Event},
    Reader, Writer,
};
use std::{collections::HashMap, io::Write, path::Path};
const NS: &str = "http://ns.adobe.com/xap/1.0/";
const RDF: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
fn is_name(name: &str, ns: &HashMap<String, String>, uri: &str, local: &str) -> bool {
    let (p, k) = name.split_once(':').unwrap_or(("", name));
    k == local && ns.get(p).is_some_and(|s| s == uri)
}
pub fn write(path: &Path, mark: &FileMark) -> Result<(), String> {
    let destination = path.with_extension("xmp");
    if destination
        .symlink_metadata()
        .is_ok_and(|m| !m.is_file() || m.file_type().is_symlink())
    {
        return Err("invalid_xmp_path".into());
    }
    let data = if destination.exists() {
        std::fs::read(&destination).map_err(|e| e.to_string())?
    } else {
        br#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about=""/></rdf:RDF></x:xmpmeta>"#.to_vec()
    };
    let mut reader = Reader::from_reader(data.as_slice());
    let mut writer = Writer::new(Vec::new());
    let mut namespaces = vec![HashMap::<String, String>::new()];
    let mut parents = Vec::<String>::new();
    let mut skip = 0usize;
    let mut targets = Vec::new();
    let mut changed = false;
    loop {
        let event = reader.read_event().map_err(|e| e.to_string())?;
        if matches!(event, Event::Eof) {
            break;
        }
        if skip > 0 {
            match event {
                Event::Start(_) => skip += 1,
                Event::End(_) => skip -= 1,
                _ => (),
            }
            continue;
        }
        match event {
            Event::Start(ref start) | Event::Empty(ref start) => {
                let mut ns = namespaces.last().cloned().unwrap_or_default();
                for attr in start.attributes() {
                    let attr = attr.map_err(|e| e.to_string())?;
                    let key = String::from_utf8_lossy(attr.key.as_ref());
                    if key == "xmlns" {
                        ns.insert(
                            "".into(),
                            attr.unescape_value()
                                .map_err(|e| e.to_string())?
                                .into_owned(),
                        );
                    } else if let Some(prefix) = key.strip_prefix("xmlns:") {
                        ns.insert(
                            prefix.into(),
                            attr.unescape_value()
                                .map_err(|e| e.to_string())?
                                .into_owned(),
                        );
                    }
                }
                let name = String::from_utf8_lossy(start.name().as_ref()).into_owned();
                let depth = parents.len();
                if targets.last() == Some(&depth)
                    && ["Rating", "Label"]
                        .iter()
                        .any(|k| is_name(&name, &ns, NS, k))
                {
                    if matches!(event, Event::Start(_)) {
                        skip = 1
                    }
                    continue;
                }
                let in_rdf = parents
                    .last()
                    .is_some_and(|p| is_name(p, namespaces.last().unwrap(), RDF, "RDF"));
                let mut main = true;
                for attr in start.attributes() {
                    let attr = attr.map_err(|e| e.to_string())?;
                    if is_name(
                        &String::from_utf8_lossy(attr.key.as_ref()),
                        &ns,
                        RDF,
                        "about",
                    ) && !attr.value.is_empty()
                    {
                        main = false
                    }
                }
                let target =
                    in_rdf && main && targets.is_empty() && is_name(&name, &ns, RDF, "Description");
                if target {
                    let mut replacement = BytesStart::new(name.clone());
                    for attr in start.attributes() {
                        let attr = attr.map_err(|e| e.to_string())?;
                        let key = String::from_utf8_lossy(attr.key.as_ref());
                        if ["Rating", "Label"]
                            .iter()
                            .any(|k| is_name(&key, &ns, NS, k))
                        {
                            continue;
                        }
                        replacement.push_attribute(attr);
                    }
                    let existing = ns
                        .iter()
                        .filter(|(k, v)| !k.is_empty() && v.as_str() == NS)
                        .map(|(k, _)| k)
                        .min()
                        .cloned();
                    let own = existing.unwrap_or_else(|| {
                        let mut p = "siftlymark".to_string();
                        while ns.contains_key(&p) {
                            p.push('x')
                        }
                        p
                    });
                    if !ns.contains_key(&own) {
                        replacement.push_attribute((format!("xmlns:{own}").as_str(), NS));
                        ns.insert(own.clone(), NS.into());
                    }
                    let stars = mark.rating.to_string();
                    replacement.push_attribute((format!("{own}:Rating").as_str(), stars.as_str()));
                    let color = match mark.label.as_str() {
                        "red" => "Red",
                        "orange" | "yellow" => "Yellow",
                        "green" => "Green",
                        "blue" => "Blue",
                        "purple" => "Purple",
                        "gray" => "Second",
                        _ => "",
                    };
                    replacement.push_attribute((format!("{own}:Label").as_str(), color));
                    changed = true;
                    writer
                        .write_event(if matches!(event, Event::Start(_)) {
                            Event::Start(replacement)
                        } else {
                            Event::Empty(replacement)
                        })
                        .map_err(|e| e.to_string())?;
                } else {
                    writer
                        .write_event(event.clone())
                        .map_err(|e| e.to_string())?
                }
                if matches!(event, Event::Start(_)) {
                    if target {
                        targets.push(depth + 1)
                    }
                    namespaces.push(ns);
                    parents.push(name)
                }
            }
            Event::End(_) => {
                if targets.last() == Some(&parents.len()) {
                    targets.pop();
                }
                parents.pop();
                namespaces.pop();
                writer.write_event(event).map_err(|e| e.to_string())?
            }
            _ => writer.write_event(event).map_err(|e| e.to_string())?,
        }
    }
    if !changed || namespaces.len() != 1 {
        return Err("invalid_xmp".into());
    }
    let mut temp = tempfile::NamedTempFile::new_in(destination.parent().ok_or("invalid_path")?)
        .map_err(|e| e.to_string())?;
    temp.write_all(&writer.into_inner())
        .map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(destination).map_err(|e| e.to_string())?;
    Ok(())
}
