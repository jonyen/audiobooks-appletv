import { expect, test } from "vitest";
import { parseBooks, stripHTML } from "./librivox";

// Fixture mirrors LibriVoxParserTests.swift exactly.
const fixture = JSON.parse(`{"books":[{
    "id":"52",
    "title":"Pride and Prejudice",
    "description":"<p>A classic novel.</p>",
    "url_text_source":"http://www.gutenberg.org/etext/1342",
    "language":"English",
    "copyright_year":"1813",
    "num_sections":"61",
    "url_iarchive":"http://www.archive.org/details/pride_prejudice_librivox",
    "coverart_jpg":"https://ia800207.us.archive.org/cover.jpg",
    "totaltime":"11:35:59",
    "totaltimesecs":41759,
    "authors":[{"id":"31","first_name":"Jane","last_name":"Austen"}],
    "genres":[{"id":"1","name":"General Fiction"}],
    "sections":[
        {"id":"100","section_number":"1","title":"Chapter 1",
         "listen_url":"https://ia800207.us.archive.org/pp_01.mp3","playtime":"1626"},
        {"id":"101","section_number":"2","title":"Chapter 2",
         "listen_url":"https://ia800207.us.archive.org/pp_02.mp3","playtime":"1417"}
    ]
},{
    "id":"99",
    "title":"No Text Book",
    "description":"",
    "url_text_source":null,
    "num_sections":"1",
    "url_iarchive":"http://www.archive.org/details/notext_librivox",
    "coverart_jpg":null,
    "totaltimesecs":100,
    "authors":[],
    "genres":[],
    "sections":[]
}]}`);

test("parses books with string numerics", () => {
  const books = parseBooks(fixture);
  expect(books.length).toBe(2);
  const pride = books[0];
  expect(pride.id).toBe(52);
  expect(pride.title).toBe("Pride and Prejudice");
  expect(pride.authors).toBe("Jane Austen");
  expect(pride.description).toBe("A classic novel.");
  expect(pride.genres).toEqual(["General Fiction"]);
  expect(pride.totalTimeSeconds).toBe(41759);
  expect(pride.sections.length).toBe(2);
  expect(pride.sections[1].playtimeSeconds).toBe(1417);
  expect(pride.sections[0].listenURL).toBe("https://ia800207.us.archive.org/pp_01.mp3");
});

test("text source is kept verbatim or null", () => {
  const books = parseBooks(fixture);
  expect(books[0].textSourceURL).toBe("http://www.gutenberg.org/etext/1342");
  expect(books[1].textSourceURL).toBeNull();
});

test("cover falls back to the archive identifier", () => {
  const books = parseBooks(fixture);
  expect(books[0].coverURL).toBe("https://ia800207.us.archive.org/cover.jpg");
  expect(books[1].coverURL).toBe("https://archive.org/services/img/notext_librivox");
});

test("error payload parses as empty", () => {
  expect(parseBooks(JSON.parse('{"error":"No results found"}')).length).toBe(0);
});

test("sections without a listen URL are dropped", () => {
  const books = parseBooks({
    books: [{ id: "1", sections: [{ id: "10", title: "No audio" }] }],
  });
  expect(books[0].sections).toEqual([]);
});

test("stripHTML", () => {
  expect(stripHTML("<p>Hi <b>there</b></p>")).toBe("Hi there");
});
